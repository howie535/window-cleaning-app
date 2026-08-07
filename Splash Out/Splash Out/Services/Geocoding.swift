import CoreLocation

enum Geocoding {
    static func coordinate(for address: String) async -> CLLocationCoordinate2D? {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            return placemarks.first?.location?.coordinate
        } catch {
            return nil
        }
    }
}
