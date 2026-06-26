import UIKit

protocol JoystickDelegate: AnyObject {
    func joystickMoved(x: Float, y: Float)
    func joystickReleased()
}

class JoystickView: UIView {
    weak var delegate: JoystickDelegate?
    private let baseSize: CGFloat = 130
    private let stickSize: CGFloat = 52
    private let maxOff: CGFloat = 40
    private var baseView: UIView!
    private var stickView: UIView!
    private var tid: UITouch?
    
    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { fatalError() }
    
    private func setup() {
        backgroundColor = .clear
        baseView = UIView()
        baseView.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        baseView.layer.cornerRadius = baseSize/2
        baseView.layer.borderWidth = 1.5
        baseView.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        baseView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(baseView)
        baseView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        baseView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        baseView.widthAnchor.constraint(equalToConstant: baseSize).isActive = true
        baseView.heightAnchor.constraint(equalToConstant: baseSize).isActive = true
        
        stickView = UIView()
        stickView.backgroundColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.3)
        stickView.layer.cornerRadius = stickSize/2
        stickView.layer.borderWidth = 1.5
        stickView.layer.borderColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.5).cgColor
        stickView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stickView)
        stickView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        stickView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        stickView.widthAnchor.constraint(equalToConstant: stickSize).isActive = true
        stickView.heightAnchor.constraint(equalToConstant: stickSize).isActive = true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tid == nil, let t = touches.first else { return }; tid = t; upd(t)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = tid, touches.contains(t) { upd(t) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { if t === tid { rel() } }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { rel() }
    
    private func upd(_ t: UITouch) {
        let c = CGPoint(x: baseView.frame.midX, y: baseView.frame.midY)
        let l = t.location(in: self)
        var dx = l.x - c.x, dy = l.y - c.y
        let d = sqrt(dx*dx+dy*dy)
        if d > maxOff { dx = dx/d*maxOff; dy = dy/d*maxOff }
        stickView.transform = CGAffineTransform(translationX: dx, y: dy)
        delegate?.joystickMoved(x: Float(dx/maxOff), y: Float(dy/maxOff))
    }
    private func rel() {
        tid = nil
        UIView.animate(withDuration: 0.12) { self.stickView.transform = .identity }
        delegate?.joystickReleased()
    }
}
