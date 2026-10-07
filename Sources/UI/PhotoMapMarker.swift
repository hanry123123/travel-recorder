import UIKit
import MapKit

final class PhotoMapMarker: MKAnnotationView {
    private let photo = UIImageView()
    private var requestID = UUID()
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>(); cache.totalCostLimit = 12*1024*1024; cache.countLimit = 160
        return cache
    }()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 48, height: 54)
        centerOffset = CGPoint(x: 0, y: -27)
        backgroundColor = .clear
        collisionMode = .rectangle; displayPriority = .defaultHigh
        canShowCallout = false
        let shape = CAShapeLayer()
        let path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 48, height: 48), cornerRadius: 7)
        path.move(to: CGPoint(x: 19, y: 47)); path.addLine(to: CGPoint(x: 24, y: 54)); path.addLine(to: CGPoint(x: 29, y: 47)); path.close()
        shape.path = path.cgPath; shape.fillColor = UIColor.white.cgColor
        layer.addSublayer(shape)
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.16
        layer.shadowRadius = 3; layer.shadowOffset = CGSize(width: 0, height: 1); layer.shadowPath = path.cgPath
        photo.frame = CGRect(x: 1.5, y: 1.5, width: 45, height: 45)
        photo.layer.cornerRadius = 5.5; photo.clipsToBounds = true
        photo.backgroundColor = .systemGray5
        addSubview(photo)
        isAccessibilityElement = true; accessibilityLabel = "旅途照片，轻点查看"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() {
        super.prepareForReuse(); requestID = UUID(); photo.image = nil
    }
    func load(_ url: URL?) {
        requestID = UUID(); let request = requestID
        photo.image = UIImage(systemName: "photo"); photo.tintColor = .secondaryLabel; photo.contentMode = .center
        guard let url = url else { return }
        func apply(_ image: UIImage?) {
            guard requestID == request, let image = image else { return }
            photo.contentMode = .scaleAspectFill; photo.image = image
        }
        if let image = Self.cache.object(forKey: url as NSURL) { apply(image); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = UIImage(contentsOfFile: url.path)
            if let image = image {
                Self.cache.setObject(image, forKey: url as NSURL, cost: (image.cgImage?.bytesPerRow ?? 0)*(image.cgImage?.height ?? 0))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.requestID == request, let image = image else { return }
                self.photo.contentMode = .scaleAspectFill; self.photo.image = image
            }
        }
    }
}
