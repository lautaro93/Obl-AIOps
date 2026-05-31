using Microsoft.Extensions.Caching.Memory;
using System.Net;

namespace PharmaGo.ApiGateway.Middleware
{
    /// <summary>
    /// Rate limiting basado en el token de autenticación del usuario
    /// en lugar de la IP, para evitar bloquear múltiples usuarios detrás de la misma IP
    /// </summary>
    public class UserRateLimitMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly IMemoryCache _cache;
        private readonly ILogger<UserRateLimitMiddleware> _logger;

        // Configuración leída desde appsettings.json (sección "RateLimiting").
        // Si los valores no están presentes se usan estos defaults.
        private readonly int _maxRequestsPerMinute;
        private readonly int _maxRequestsPerHour;
        private readonly int _loginMaxRequestsPerMinute;
        // Endpoints que no se limitan (health checks, métricas, preflight CORS).
        // Formato "metodo:path", igual que el modo IP. Ej: "get:/health", "options:*".
        private readonly List<string> _endpointWhitelist;

        public UserRateLimitMiddleware(
            RequestDelegate next,
            IMemoryCache cache,
            ILogger<UserRateLimitMiddleware> logger,
            IConfiguration configuration)
        {
            _next = next;
            _cache = cache;
            _logger = logger;

            _maxRequestsPerMinute = configuration.GetValue<int?>("RateLimiting:MaxRequestsPerMinute") ?? 100;
            _maxRequestsPerHour = configuration.GetValue<int?>("RateLimiting:MaxRequestsPerHour") ?? 1000;
            _loginMaxRequestsPerMinute = configuration.GetValue<int?>("RateLimiting:LoginMaxRequestsPerMinute") ?? 10;
            _endpointWhitelist = configuration.GetSection("RateLimiting:EndpointWhitelist").Get<List<string>>()
                ?? new List<string>();
        }

        public async Task InvokeAsync(HttpContext context)
        {
            // Los endpoints en whitelist (health, métricas, preflight) no se limitan
            if (IsWhitelisted(context))
            {
                await _next(context);
                return;
            }

            // Obtener identificador del usuario (token o IP como fallback)
            var identifier = GetUserIdentifier(context);

            // El login tiene un límite por minuto más estricto (anti brute-force)
            var isLogin = IsLoginEndpoint(context);

            // Verificar límites
            if (!CheckRateLimit(identifier, isLogin, out string reason))
            {
                _logger.LogWarning($"Rate limit exceeded for {identifier}: {reason}");

                context.Response.StatusCode = (int)HttpStatusCode.TooManyRequests;
                context.Response.Headers.Add("X-RateLimit-Reason", reason);
                await context.Response.WriteAsJsonAsync(new
                {
                    error = "Too many requests",
                    message = reason,
                    retryAfter = "60 seconds"
                });
                return;
            }

            await _next(context);
        }

        private bool IsWhitelisted(HttpContext context)
        {
            if (_endpointWhitelist.Count == 0)
            {
                return false;
            }

            var method = context.Request.Method;
            var path = context.Request.Path.Value ?? string.Empty;

            foreach (var entry in _endpointWhitelist)
            {
                var parts = entry.Split(':', 2);
                if (parts.Length != 2)
                {
                    continue;
                }

                var ruleMethod = parts[0].Trim();
                var rulePath = parts[1].Trim();

                var methodMatches = ruleMethod == "*"
                    || ruleMethod.Equals(method, StringComparison.OrdinalIgnoreCase);
                if (!methodMatches)
                {
                    continue;
                }

                var pathMatches = rulePath == "*"
                    || (rulePath.EndsWith("*") && path.StartsWith(rulePath[..^1], StringComparison.OrdinalIgnoreCase))
                    || rulePath.Equals(path, StringComparison.OrdinalIgnoreCase);
                if (pathMatches)
                {
                    return true;
                }
            }

            return false;
        }

        private static bool IsLoginEndpoint(HttpContext context)
        {
            return HttpMethods.IsPost(context.Request.Method)
                && context.Request.Path.StartsWithSegments("/api/login", StringComparison.OrdinalIgnoreCase);
        }

        private string GetUserIdentifier(HttpContext context)
        {
            // 1. Intentar obtener token de autorización
            if (context.Request.Headers.TryGetValue("Authorization", out var authHeader))
            {
                var token = authHeader.ToString().Replace("Bearer ", "");
                if (!string.IsNullOrEmpty(token))
                {
                    return $"user:{token.Substring(0, Math.Min(8, token.Length))}"; // Usar primeros 8 chars
                }
            }

            // 2. Intentar obtener X-User-Id (si el frontend lo envía)
            if (context.Request.Headers.TryGetValue("X-User-Id", out var userId))
            {
                return $"user:{userId}";
            }

            // 3. Fallback a IP (para endpoints públicos como login)
            var ip = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";

            // Si viene de un proxy, intentar obtener la IP real
            if (context.Request.Headers.TryGetValue("X-Forwarded-For", out var forwardedFor))
            {
                ip = forwardedFor.ToString().Split(',')[0].Trim();
            }
            else if (context.Request.Headers.TryGetValue("X-Real-IP", out var realIp))
            {
                ip = realIp.ToString();
            }

            return $"ip:{ip}";
        }

        private bool CheckRateLimit(string identifier, bool isLogin, out string reason)
        {
            var now = DateTime.UtcNow;

            // El login usa su propio límite y su propio contador (aislado del tráfico general)
            var perMinuteLimit = isLogin ? _loginMaxRequestsPerMinute : _maxRequestsPerMinute;
            var scope = isLogin ? "login" : "general";

            // Verificar límite por minuto
            var minuteKey = $"{identifier}:{scope}:minute:{now:yyyyMMddHHmm}";
            var minuteCount = _cache.GetOrCreate(minuteKey, entry =>
            {
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1);
                return 0;
            });

            if (minuteCount >= perMinuteLimit)
            {
                reason = $"Exceeded {perMinuteLimit} requests per minute";
                return false;
            }

            // Verificar límite por hora (solo para tráfico general; el login solo limita por minuto)
            if (!isLogin)
            {
                var hourKey = $"{identifier}:hour:{now:yyyyMMddHH}";
                var hourCount = _cache.GetOrCreate(hourKey, entry =>
                {
                    entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1);
                    return 0;
                });

                if (hourCount >= _maxRequestsPerHour)
                {
                    reason = $"Exceeded {_maxRequestsPerHour} requests per hour";
                    return false;
                }

                _cache.Set(hourKey, hourCount + 1, TimeSpan.FromHours(1));
            }

            // Incrementar contador por minuto
            _cache.Set(minuteKey, minuteCount + 1, TimeSpan.FromMinutes(1));

            reason = string.Empty;
            return true;
        }
    }

    public static class UserRateLimitMiddlewareExtensions
    {
        public static IApplicationBuilder UseUserRateLimit(this IApplicationBuilder builder)
        {
            return builder.UseMiddleware<UserRateLimitMiddleware>();
        }
    }
}
