import Foundation

/// Builds URLs by safely percent-encoding untrusted path segments.
public enum OpenAIURLPathBuilder {
    private static let allowedPathSegmentCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    /// Resolves a URL from a base URL and raw path segments.
    /// - Parameters:
    ///   - baseURL: The service base URL, which may already include a path prefix.
    ///   - pathSegments: Raw path segments that should each be encoded independently.
    ///   - queryItems: Optional query items.
    /// - Returns: A fully constructed URL or `nil` when encoding fails.
    public static func url(
        baseURL: String,
        pathSegments: [String],
        queryItems: [URLQueryItem]? = nil
    ) -> URL? {
        guard var components = URLComponents(string: baseURL) else {
            return nil
        }

        let baseSegments = components.percentEncodedPath
            .split(separator: "/")
            .map(String.init)

        var encodedSegments: [String] = []
        encodedSegments.reserveCapacity(pathSegments.count)
        for segment in pathSegments {
            guard let encodedSegment = segment.addingPercentEncoding(
                withAllowedCharacters: allowedPathSegmentCharacters
            ) else {
                return nil
            }
            encodedSegments.append(encodedSegment)
        }

        let combinedSegments = baseSegments + encodedSegments
        components.percentEncodedPath = "/" + combinedSegments.joined(separator: "/")
        components.queryItems = queryItems?.isEmpty == false ? queryItems : nil
        return components.url
    }
}
