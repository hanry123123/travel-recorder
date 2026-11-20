import UIKit
import MapKit

final class PhotoMapMarker: MKAnnotationView {
    private let photo = UIImageView()
    private var requestID = UUID()
    private var loadedURL: URL?
    private var hasActualImage = false
    private let badge = UILabel()
    func setCount(_ count: Int) {
        badge.text = "\(count)"; badge.isHidden = count < 2
        accessibilityLabel = count > 1 ? (AppLanguage.english ? "\(count) photos here, tap to view" : "这里有\(count)张照片，轻点查看") : L("旅途照片，轻点查看")
    }
    private var imageRequest: PhotoImageRequest?
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 48, height: 54)
        centerOffset = CGPoint(x: 0, y: -27)
        backgroundColor = .clear
        collisionMode = .rectangle; displayPriority = .required
        clusteringIdentifier = "tripPhotos"
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
        badge.frame = CGRect(x: 28, y: -5, width: 24, height: 20)
        badge.backgroundColor = .systemBlue; badge.textColor = .white
        badge.font = .systemFont(ofSize: 11, weight: .bold); badge.textAlignment = .center
        badge.layer.cornerRadius = 10; badge.clipsToBounds = true; badge.isHidden = true
        addSubview(badge)
        isAccessibilityElement = true; accessibilityLabel = L("旅途照片，轻点查看")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() {
        super.prepareForReuse(); imageRequest?.cancel(); requestID = UUID(); loadedURL = nil; hasActualImage = false; photo.image = nil; setCount(1)
    }
    func load(_ url: URL?) {
        if loadedURL == url && hasActualImage { return }
        imageRequest?.cancel(); loadedURL = url; hasActualImage = false
        requestID = UUID(); let request = requestID
        photo.image = UIImage(systemName: "photo"); photo.tintColor = .secondaryLabel; photo.contentMode = .center
        guard let url = url else { return }
        imageRequest = PhotoImageLoader.load(url, edge: 160) { [weak self] image in
            guard let self = self, self.requestID == request, let image = image else { return }
            self.hasActualImage = true; self.photo.contentMode = .scaleAspectFill; self.photo.image = image
        }
    }
    deinit { imageRequest?.cancel() }
}
