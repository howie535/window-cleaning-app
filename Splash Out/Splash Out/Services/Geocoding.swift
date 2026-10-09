import CoreLocation
import MapKit

enum Geocoding {
    static func coordinate(for address: String) async -> CLLocationCoordinate2D? {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }
        do {
            let items = try await request.mapItems
            return items.first?.location.coordinate
        } catch {
            return nil
        }
    }
}
