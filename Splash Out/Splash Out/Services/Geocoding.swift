import CoreLocation
import MapKit

enum Geocoding {
    static func coordinate(for address: String) async -> CLLocationCoordinate2D? {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if #available(iOS 26.0, *) {
            guard let request = MKGeocodingRequest(addressString: address) else { return nil }
            do {
                let items = try await request.mapItems
                return items.first?.location.coordinate
            } catch {
                return nil
            }
        } else {
            // iOS 18 (the iPhone 12 and iPad): the older geocoder, which Apple replaced in iOS 26.
            let placemarks = try? await CLGeocoder().geocodeAddressString(address)
            return placemarks?.first?.location?.coordinate
        }
    }
}
