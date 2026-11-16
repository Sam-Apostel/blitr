import SwiftUI
import UIKit

// UIKit views that draw themselves (`draw(_:)` with UIKit and Core Graphics calls) or arrange stock
// UIKit subviews (frames set in `layoutSubviews`, simple Auto Layout, UIStackView), wrapped in
// UIViewRepresentable. Sizes come from `sizeThatFits(_:uiView:context:)` or the view's
// `intrinsicContentSize`; the last one holds a control that cannot be drawn and stays a placeholder.

/// A bar chart drawn in `draw(_:)`: UIBezierPath bars, a Core Graphics baseline and NSString labels.
final class BarChartView: UIView {
    var values: [CGFloat] = []
    var labels: [String] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !values.isEmpty else { return }
        let labelHeight: CGFloat = 16
        let plot = bounds.insetBy(dx: 4, dy: 4).divided(atDistance: labelHeight, from: .maxYEdge).remainder
        let slot = plot.width / CGFloat(values.count)
        let top = values.max() ?? 1
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        for (index, value) in values.enumerated() {
            let height = plot.height * value / top
            let bar = CGRect(x: plot.minX + CGFloat(index) * slot + slot * 0.2, y: plot.maxY - height, width: slot * 0.6, height: height)
            (index == values.count - 1 ? UIColor.systemOrange : UIColor.systemBlue).setFill()
            UIBezierPath(roundedRect: bar, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 4, height: 4)).fill()
            if index < labels.count {
                let text = labels[index] as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: bar.midX - size.width / 2, y: plot.maxY + 2), withAttributes: attributes)
            }
        }
        context.setStrokeColor(UIColor.separator.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: plot.minX, y: plot.maxY + 0.5))
        context.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY + 0.5))
        context.strokePath()
    }
}

struct BarChart: UIViewRepresentable {
    let values: [CGFloat]
    let labels: [String]
    func makeUIView(context: Context) -> BarChartView { BarChartView() }
    func updateUIView(_ view: BarChartView, context: Context) {
        view.values = values
        view.labels = labels
        view.setNeedsDisplay()
    }
}

/// A ring gauge that reports its own size: drawn with arcs, a fixed intrinsic content size that it hugs.
final class RingGaugeView: UIView {
    var progress: CGFloat = 0.6

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: 64, height: 64) }

    override func draw(_ rect: CGRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 6
        let track = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        track.lineWidth = 8
        UIColor.systemGray5.setStroke()
        track.stroke()
        let arc = UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi / 2, endAngle: -.pi / 2 + .pi * 2 * progress, clockwise: true)
        arc.lineWidth = 8
        arc.lineCapStyle = .round
        UIColor.systemGreen.setStroke()
        arc.stroke()
        let text = "\(Int(progress * 100))%" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.label]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }
}

struct RingGauge: UIViewRepresentable {
    let progress: CGFloat
    func makeUIView(context: Context) -> RingGaugeView { RingGaugeView() }
    func updateUIView(_ view: RingGaugeView, context: Context) { view.progress = progress }
}

/// A row built from stock views: an icon and two labels in stack views, on a rounded, bordered card.
struct ContactRow: UIViewRepresentable {
    let name: String
    let detail: String

    func makeUIView(context: Context) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.systemGray4.cgColor

        let icon = UIImageView(image: UIImage(systemName: "person.crop.circle.fill"))
        icon.tintColor = .systemIndigo
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let title = UILabel()
        title.text = name
        title.font = .preferredFont(forTextStyle: .headline)
        let subtitle = UILabel()
        subtitle.text = detail
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .secondaryLabel

        let text = UIStackView(arrangedSubviews: [title, subtitle])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }
    func updateUIView(_ view: UIView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 64)
    }
}

/// A progress bar whose track and fill are placed by hand in `layoutSubviews`, with a gradient sublayer.
final class SegmentedProgressView: UIView {
    var progress: CGFloat = 0.4
    private let fill = UIView()
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGray5
        layer.cornerRadius = 6
        clipsToBounds = true
        gradient.colors = [UIColor.systemTeal.cgColor, UIColor.systemBlue.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        fill.layer.addSublayer(gradient)
        fill.layer.cornerRadius = 6
        fill.clipsToBounds = true
        addSubview(fill)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height)
        gradient.frame = fill.bounds
    }
}

struct SegmentedProgress: UIViewRepresentable {
    let progress: CGFloat
    func makeUIView(context: Context) -> SegmentedProgressView { SegmentedProgressView() }
    func updateUIView(_ view: SegmentedProgressView, context: Context) { view.progress = progress }
}

/// Two stock buttons side by side, filled equally: a configuration button and a classic one.
struct ButtonBar: UIViewRepresentable {
    func makeUIView(context: Context) -> UIStackView {
        var filled = UIButton.Configuration.filled()
        filled.title = "Accept"
        let accept = UIButton(configuration: filled)
        let decline = UIButton(type: .system)
        decline.setTitle("Decline", for: .normal)
        decline.setTitleColor(.systemRed, for: .normal)
        let stack = UIStackView(arrangedSubviews: [decline, accept])
        stack.distribution = .fillEqually
        stack.spacing = 12
        return stack
    }
    func updateUIView(_ view: UIStackView, context: Context) {}
}

/// A stack holding a segmented control, which is not drawn: the whole view is a placeholder.
struct FilterBar: UIViewRepresentable {
    func makeUIView(context: Context) -> UIStackView {
        let label = UILabel()
        label.text = "Show"
        let control = UISegmentedControl(items: ["All", "Unread"])
        control.selectedSegmentIndex = 0
        return UIStackView(arrangedSubviews: [label, control])
    }
    func updateUIView(_ view: UIStackView, context: Context) {}
}

#Preview("UIKit view trees") {
    VStack(alignment: .leading, spacing: 16) {
        BarChart(values: [3, 5, 4, 7, 6, 9], labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
            .frame(height: 140)
        HStack(spacing: 16) {
            RingGauge(progress: 0.72)
            VStack(alignment: .leading, spacing: 8) {
                Text("Weekly goal").font(.headline)
                SegmentedProgress(progress: 0.72).frame(height: 12)
            }
        }
        ContactRow(name: "Robin Example", detail: "Product design")
        ButtonBar().frame(height: 44)
        FilterBar().frame(height: 32)
    }
    .padding()
}
