import UIKit
import SceneKit
import AVFoundation

class GameViewController: UIViewController {
    
    // Scene
    private var sv: SCNView!
    private var scene: SCNScene!
    private var cam: SCNNode!
    
    // Maze
    private let cs: CGFloat = 4.0
    private let wh: CGFloat = 3.2
    private let gw = 12, gh = 12
    private var maze: MazeGenerator!
    private var walls: [SCNNode] = []
    
    // Player
    private var pY: Float = 0.3
    private let standY: Float = 1.6
    private var yaw: Float = 0, pitch: Float = 0
    private var stam: Float = 1.0
    private var sprinting = false, waking = true, inMenu = true
    private var wakeT: Float = 0
    private var bobT: Float = 0, bobA: Float = 0, shakeA: Float = 0, heaveA: Float = 0
    private var jX: Float = 0, jY: Float = 0
    private var lastT: TimeInterval = 0
    private var stepClk: Float = 0, breathClk: Float = 0
    
    // Audio
    private var buzzP: AVAudioPlayer?
    private var stepP: AVAudioPlayer?
    private var breathP: AVAudioPlayer?
    private var heavyP: AVAudioPlayer?
    private var doorP: AVAudioPlayer?
    private var audioOn = false
    
    // Lights
    private var lts: [SCNNode] = []
    private var glows: [SCNNode] = []
    
    // Interactables
    private var doors: [(node: SCNNode, open: Bool, angle: Float)] = []
    private var drawers: [(node: SCNNode, open: Bool, offset: Float)] = []
    
    // Textures
    private var wallImg: UIImage!
    private var carpImg: UIImage!
    private var ceilImg: UIImage!
    private var lampImg: UIImage!
    private var metImg: UIImage!
    private var woodImg: UIImage!
    private var baseImg: UIImage!
    private var colImg: UIImage!
    
    // UI
    private var joystick: JoystickView!
    private var runBtn: UIButton!
    private var interactBtn: UIButton!
    private var stamBar: UIView!
    private var stamFill: UIView!
    private var redOv: UIView!
    private var menuOv: UIView!
    private var promptLabel: UILabel!
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        loadRes()
        setupScene()
        buildLevel()
        setupUI()
        showMenu()
        lastT = CACurrentMediaTime()
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        dl.add(to: .main, forMode: .common)
    }
    
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    
    // MARK: - Resources
    private func loadRes() {
        let b = Bundle.main
        wallImg = img("wall", b); carpImg = img("carpet", b); ceilImg = img("ceiling", b)
        lampImg = img("lamp", b); metImg = img("metal", b); woodImg = img("wood", b)
        baseImg = img("baseboard", b); colImg = img("column", b)
    }
    private func img(_ n: String, _ b: Bundle) -> UIImage {
        if let u = b.url(forResource: n, withExtension: "png", subdirectory: "Resources"),
           let i = UIImage(contentsOfFile: u.path) { return i }
        return UIImage(named: n) ?? UIImage()
    }
    private func wav(_ n: String) -> URL? {
        let b = Bundle.main
        return b.url(forResource: n, withExtension: "wav", subdirectory: "Resources")
            ?? b.url(forResource: n, withExtension: "wav")
    }
    
    private func initAudio() {
        guard !audioOn else { return }; audioOn = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        if let u = wav("buzz") { buzzP = try? AVAudioPlayer(contentsOf: u); buzzP?.numberOfLoops = -1; buzzP?.volume = 0.35; buzzP?.play() }
        if let u = wav("step") { stepP = try? AVAudioPlayer(contentsOf: u); stepP?.volume = 0.5; stepP?.prepareToPlay() }
        if let u = wav("breath") { breathP = try? AVAudioPlayer(contentsOf: u); breathP?.volume = 0.3; breathP?.prepareToPlay() }
        if let u = wav("heavy_breath") { heavyP = try? AVAudioPlayer(contentsOf: u); heavyP?.volume = 0.4; heavyP?.prepareToPlay() }
        // Generate door sound procedurally if no file
        if let u = wav("door") { doorP = try? AVAudioPlayer(contentsOf: u); doorP?.volume = 0.6; doorP?.prepareToPlay() }
    }
    
    private func playStep() { stepP?.currentTime = 0; stepP?.play() }
    private func playBreath() { let p = stam < 0.3 ? heavyP : breathP; p?.currentTime = 0; p?.play() }
    private func playDoor() {
        // Simple click sound if no door.wav
        AudioServicesPlaySystemSound(1104)
    }
    
    // MARK: - Scene
    private func setupScene() {
        sv = SCNView(frame: view.bounds)
        sv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sv.backgroundColor = UIColor(red: 0.78, green: 0.71, blue: 0.38, alpha: 1)
        sv.antialiasingMode = .multisampling2X
        view.addSubview(sv)
        
        scene = SCNScene(); sv.scene = scene
        scene.fogStartDistance = 1
        scene.fogEndDistance = 40
        scene.fogColor = UIColor(red: 0.78, green: 0.71, blue: 0.38, alpha: 1)
        
        cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.fieldOfView = 72
        cam.camera!.zNear = 0.05; cam.camera!.zFar = 55
        cam.camera!.wantsHDR = true
        cam.camera!.exposureOffset = 0.1
        cam.position = SCNVector3(Float(cs/2), pY, Float(cs/2))
        scene.rootNode.addChildNode(cam)
        sv.pointOfView = cam
    }
    
    // MARK: - Build
    private func buildLevel() {
        maze = MazeGenerator(width: gw, height: gh)
        maze.generate()
        
        let wM = mat(wallImg, 2, 1)
        let fM = mat(carpImg, 8, 8)
        let cM = mat(ceilImg, 4, 4)
        let mM = mat(metImg)
        let bM = mat(baseImg)
        let coM = mat(colImg)
        let wdM = mat(woodImg)
        let drM = mat(woodImg) // door material
        
        let wH = SCNBox(width: cs, height: wh, length: 0.12, chamferRadius: 0)
        let wV = SCNBox(width: 0.12, height: wh, length: cs, chamferRadius: 0)
        let bH = SCNBox(width: cs, height: 0.12, length: 0.06, chamferRadius: 0)
        let bV = SCNBox(width: 0.06, height: 0.12, length: cs, chamferRadius: 0)
        
        for y in 0..<gh { for x in 0..<gw {
            let cx = CGFloat(x) * cs + cs/2
            let cz = CGFloat(y) * cs + cs/2
            let c = maze.grid[y][x]
            let cellW = c.isSpecial ? mat(forType: c.specialType, base: wM) : wM
            
            if c.north { addW(wH, cellW, cx, wh/2, cz - cs/2); addB(bH, bM, cx, 0.06, cz - cs/2 + 0.07) }
            if c.south { addW(wH, cellW, cx, wh/2, cz + cs/2); addB(bH, bM, cx, 0.06, cz + cs/2 - 0.07) }
            if c.east  { addW(wV, cellW, cx + cs/2, wh/2, cz); addB(bV, bM, cx + cs/2 - 0.07, 0.06, cz) }
            if c.west  { addW(wV, cellW, cx - cs/2, wh/2, cz); addB(bV, bM, cx - cs/2 + 0.07, 0.06, cz) }
        }}
        
        let bw = CGFloat(gw) * cs, bh = CGFloat(gh) * cs
        let bWH = SCNBox(width: bw, height: wh, length: 0.15, chamferRadius: 0)
        addW(bWH, wM, bw/2, wh/2, 0); addW(bWH, wM, bw/2, wh/2, bh)
        let bWV = SCNBox(width: 0.15, height: wh, length: bh, chamferRadius: 0)
        addW(bWV, wM, 0, wh/2, bh/2); addW(bWV, wM, bw, wh/2, bh/2)
        
        // Floor
        let fg = SCNBox(width: bw, height: 0.02, length: bh, chamferRadius: 0)
        fg.materials = [fM]
        let fn = SCNNode(geometry: fg); fn.position = SCNVector3(Float(bw/2), -0.01, Float(bh/2))
        scene.rootNode.addChildNode(fn)
        
        // Ceiling
        let cg = SCNBox(width: bw, height: 0.05, length: bh, chamferRadius: 0)
        cg.materials = [cM]
        let cn = SCNNode(geometry: cg); cn.position = SCNVector3(Float(bw/2), Float(wh), Float(bh/2))
        scene.rootNode.addChildNode(cn)
        
        // Lamps (only every 3rd cell for performance)
        for y in stride(from: 0, to: gh, by: 2) { for x in stride(from: 0, to: gw, by: 2) {
            let lx = CGFloat(x) * cs + cs/2, lz = CGFloat(y) * cs + cs/2
            let cell = maze.grid[y][x]
            let broken = Float.random(in: 0...1) < 0.1
            let darkRoom = cell.isSpecial && cell.specialType == .dark
            addLamp(x: lx, z: lz, broken: broken || darkRoom, special: cell.specialType)
        }}
        
        // Ambient
        let al = SCNLight(); al.type = .ambient; al.color = UIColor(red:1, green:0.99, blue:0.88, alpha:1); al.intensity = 80
        let an = SCNNode(); an.light = al; scene.rootNode.addChildNode(an)
        
        // Columns
        let colG = SCNBox(width: 0.28, height: wh, length: 0.28, chamferRadius: 0)
        colG.materials = [coM]
        for y in stride(from: 2, to: gh, by: 3) { for x in stride(from: 2, to: gw, by: 3) {
            if Float.random(in: 0...1) < 0.4 {
                let px = CGFloat(x)*cs + cs/2 + CGFloat(Float.random(in:-0.6...0.6))
                let pz = CGFloat(y)*cs + cs/2 + CGFloat(Float.random(in:-0.6...0.6))
                let col = SCNNode(geometry: colG)
                col.position = SCNVector3(Float(px), Float(wh/2), Float(pz))
                scene.rootNode.addChildNode(col); walls.append(col)
            }
        }}
        
        // Pipes
        let pg = SCNCylinder(radius: 0.04, height: bw); pg.materials = [mM]
        for z in stride(from: 2, to: gh, by: 6) {
            let p = SCNNode(geometry: pg)
            p.eulerAngles = SCNVector3(0, 0, Float.pi/2)
            p.position = SCNVector3(Float(bw/2), Float(wh-0.12), Float(CGFloat(z)*cs + cs/2))
            scene.rootNode.addChildNode(p)
        }
        
        // Furniture
        for y in stride(from: 1, to: gh, by: 3) { for x in stride(from: 1, to: gw, by: 3) {
            if Float.random(in: 0...1) < 0.35 {
                addTable(x: CGFloat(x)*cs+cs/2, z: CGFloat(y)*cs+cs/2+0.5, m: wdM)
            }
            if Float.random(in: 0...1) < 0.25 {
                addCabinet(x: CGFloat(x)*cs+cs/2-0.5, z: CGFloat(y)*cs+cs/2, m: wdM)
            }
        }}
        
        // Doors
        for y in stride(from: 1, to: gh, by: 4) { for x in stride(from: 0, to: gw, by: 5) {
            if Float.random(in: 0...1) < 0.5 {
                addDoor(x: CGFloat(x)*cs+cs/2, z: CGFloat(y)*cs, m: drM, axis: 0)
            }
        }}
    }
    
    private func mat(forType: SpecialType, base: SCNMaterial) -> SCNMaterial {
        let m = base.copy() as! SCNMaterial
        switch forType {
        case .red:
            m.diffuse.contents = UIColor(red: 0.5, green: 0.15, blue: 0.1, alpha: 1)
            m.emission.contents = UIColor(red: 0.15, green: 0.02, blue: 0.01, alpha: 1)
            m.emission.intensity = 0.3
        case .dark:
            m.diffuse.contents = UIColor(red: 0.15, green: 0.12, blue: 0.08, alpha: 1)
        case .flooded:
            m.diffuse.contents = UIColor(red: 0.3, green: 0.35, blue: 0.25, alpha: 1)
        default: break
        }
        return m
    }
    
    private func addLamp(x: CGFloat, z: CGFloat, broken: Bool, special: SpecialType) {
        let mMat = mat(metImg)
        // Housing
        let hg = SCNBox(width: 1.3, height: 0.06, length: 0.35, chamferRadius: 0); hg.materials = [mMat]
        let h = SCNNode(geometry: hg); h.position = SCNVector3(Float(x), Float(wh-0.03), Float(z))
        scene.rootNode.addChildNode(h)
        // End caps
        for sx: CGFloat in [-0.65, 0.65] {
            let cg = SCNBox(width: 0.06, height: 0.08, length: 0.35, chamferRadius: 0); cg.materials = [mMat]
            let c = SCNNode(geometry: cg); c.position = SCNVector3(Float(x+sx), Float(wh-0.04), Float(z))
            scene.rootNode.addChildNode(c)
        }
        // Wires
        for sx: CGFloat in [-0.4, 0.4] {
            let wg = SCNCylinder(radius: 0.008, height: 0.15); wg.materials = [mMat]
            let w = SCNNode(geometry: wg); w.position = SCNVector3(Float(x+sx), Float(wh-0.1), Float(z))
            scene.rootNode.addChildNode(w)
        }
        // Tube
        let tg = SCNBox(width: 1.15, height: 0.02, length: 0.26, chamferRadius: 0)
        let tMat = SCNMaterial()
        tMat.emission.contents = lampImg
        tMat.emission.intensity = broken ? 0.05 : 2.0
        tMat.diffuse.contents = UIColor(white: 1, alpha: 0.9)
        tMat.isDoubleSided = true
        tg.materials = [tMat]
        let t = SCNNode(geometry: tg); t.position = SCNVector3(Float(x), Float(wh-0.07), Float(z))
        scene.rootNode.addChildNode(t); glows.append(t)
        
        // Light cone (visible volumetric-like)
        if !broken {
            let cone = SCNCone(topRadius: 0.3, bottomRadius: 2.0, height: CGFloat(wh - 0.3))
            let coneMat = SCNMaterial()
            coneMat.diffuse.contents = UIColor(red: 1, green: 0.98, blue: 0.85, alpha: 0.02)
            coneMat.transparent.contents = UIColor(white: 1, alpha: 0.02)
            coneMat.isDoubleSided = true
            coneMat.transparencyMode = .default
            cone.materials = [coneMat]
            let coneN = SCNNode(geometry: cone)
            coneN.position = SCNVector3(Float(x), Float(wh/2 - 0.1), Float(z))
            scene.rootNode.addChildNode(coneN)
        }
        
        // Point light — NO shadows for performance, only 4 nearest get shadows
        let l = SCNLight()
        l.type = .omni
        let lColor: UIColor
        switch special {
        case .red: lColor = UIColor(red: 1, green: 0.6, blue: 0.5, alpha: 1)
        case .flooded: lColor = UIColor(red: 0.9, green: 1, blue: 0.85, alpha: 1)
        default: lColor = UIColor(red: 1, green: 0.99, blue: 0.88, alpha: 1)
        }
        l.color = lColor
        l.intensity = broken ? 0 : 1500
        l.attenuationStartDistance = 0.5
        l.attenuationEndDistance = 12
        l.attenuationFalloffExponent = 2
        l.castsShadow = false // Performance! Will enable for nearest only
        let ln = SCNNode(); ln.light = l
        ln.position = SCNVector3(Float(x), Float(wh-0.25), Float(z))
        scene.rootNode.addChildNode(ln); lts.append(ln)
    }
    
    // Table
    private func addTable(x: CGFloat, z: CGFloat, m: SCNMaterial) {
        let p = SCNNode(); p.position = SCNVector3(Float(x), 0, Float(z))
        p.eulerAngles.y = Float.random(in: 0...Float.pi)
        let top = SCNBox(width: 1.2, height: 0.05, length: 0.8, chamferRadius: 0)
        top.materials = [m]; let tn = SCNNode(geometry: top); tn.position = SCNVector3(0, 0.75, 0)
        p.addChildNode(tn)
        let lg = SCNBox(width: 0.05, height: 0.75, length: 0.05, chamferRadius: 0); lg.materials = [m]
        for (lx,lz) in [(0.5,0.3),(-0.5,0.3),(0.5,-0.3),(-0.5,-0.3)] {
            let l = SCNNode(geometry: lg); l.position = SCNVector3(Float(lx), 0.375, Float(lz))
            p.addChildNode(l); walls.append(l)
        }
        scene.rootNode.addChildNode(p)
    }
    
    // Cabinet with interactable drawers
    private func addCabinet(x: CGFloat, z: CGFloat, m: SCNMaterial) {
        let p = SCNNode(); p.position = SCNVector3(Float(x), 0, Float(z))
        p.eulerAngles.y = Float.random(in: 0...Float.pi)
        let bg = SCNBox(width: 0.5, height: 1.3, length: 0.4, chamferRadius: 0)
        bg.materials = [m]; let bn = SCNNode(geometry: bg); bn.position = SCNVector3(0, 0.65, 0)
        p.addChildNode(bn); walls.append(bn)
        // Drawer handles
        let hM = mat(metImg); hM.metalness.contents = UIColor(white: 0.8, alpha: 1)
        for dy: Float in [0.3, 0.6, 0.9] {
            let dg = SCNBox(width: 0.4, height: 0.2, length: 0.38, chamferRadius: 0)
            let dM = m.copy() as! SCNMaterial; dM.diffuse.contents = UIColor(white: 0.7, alpha: 1)
            dg.materials = [dM]
            let dn = SCNNode(geometry: dg); dn.position = SCNVector3(0, dy, 0.01)
            dn.name = "drawer"
            p.addChildNode(dn)
            drawers.append((node: dn, open: false, offset: 0))
            // Handle
            let hg = SCNBox(width: 0.1, height: 0.02, length: 0.03, chamferRadius: 0); hg.materials = [hM]
            let hn = SCNNode(geometry: hg); hn.position = SCNVector3(0, dy, 0.21)
            p.addChildNode(hn)
        }
        scene.rootNode.addChildNode(p)
    }
    
    // Door
    private func addDoor(x: CGFloat, z: CGFloat, m: SCNMaterial, axis: Float) {
        let dg = SCNBox(width: 0.9, height: 2.2, length: 0.06, chamferRadius: 0)
        dg.materials = [m]
        let dn = SCNNode(geometry: dg)
        dn.position = SCNVector3(Float(x), 1.1, Float(z))
        dn.name = "door"
        scene.rootNode.addChildNode(dn)
        walls.append(dn)
        doors.append((node: dn, open: false, angle: 0))
        // Handle
        let hg = SCNBox(width: 0.06, height: 0.12, length: 0.08, chamferRadius: 0)
        let hM = mat(metImg); hM.metalness.contents = UIColor(white: 0.8, alpha: 1)
        hg.materials = [hM]
        let hn = SCNNode(geometry: hg); hn.position = SCNVector3(0.35, 0, 0.05)
        dn.addChildNode(hn)
    }
    
    private func addW(_ geo: SCNGeometry, _ m: SCNMaterial, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        let n = SCNNode(geometry: geo); n.geometry?.materials = [m]
        n.position = SCNVector3(Float(x), Float(y), Float(z))
        scene.rootNode.addChildNode(n); walls.append(n)
    }
    private func addB(_ geo: SCNGeometry, _ m: SCNMaterial, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        let n = SCNNode(geometry: geo); n.geometry?.materials = [m]
        n.position = SCNVector3(Float(x), Float(y), Float(z)); scene.rootNode.addChildNode(n)
    }
    private func mat(_ img: UIImage, _ rx: Int = 1, _ ry: Int = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = img; m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(rx), Float(ry), 1)
        m.roughness.contents = UIColor(white: 0.85, alpha: 1); m.locksAmbientWithDiffuse = true
        return m
    }
    
    // MARK: - Collision
    private func collides(_ nx: Float, _ nz: Float) -> Bool {
        for w in walls {
            let wp = w.presentation.worldPosition
            let (mn, mx) = w.boundingBox
            let hw = (mx.x - mn.x)/2 + 0.3
            let hd = (mx.z - mn.z)/2 + 0.3
            if abs(nx - wp.x) < hw && abs(nz - wp.z) < hd { return true }
        }
        return false
    }
    
    // MARK: - Interaction
    private func tryInteract() {
        let pos = cam.position
        let dir = SCNVector3(-sin(yaw), 0, -cos(yaw))
        
        // Check doors
        for i in 0..<doors.count {
            var d = doors[i]
            let dp = d.node.presentation.worldPosition
            let dx = pos.x - dp.x, dz = pos.z - dp.z
            if dx*dx + dz*dz < 4.0 {
                d.open = !d.open
                playDoor()
                doors[i] = d
                return
            }
        }
        
        // Check drawers
        for i in 0..<drawers.count {
            var dr = drawers[i]
            let dp = dr.node.presentation.worldPosition
            let dx = pos.x - dp.x, dz = pos.z - dp.z
            if dx*dx + dz*dz < 3.0 {
                dr.open = !dr.open
                playDoor()
                drawers[i] = dr
                return
            }
        }
    }
    
    // MARK: - UI
    private func setupUI() {
        // Red overlay (low stamina)
        redOv = UIView(frame: view.bounds)
        redOv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        redOv.isUserInteractionEnabled = false; redOv.alpha = 0
        let rl = CAGradientLayer()
        rl.colors = [UIColor.clear.cgColor, UIColor(red: 0.4, green: 0.05, blue: 0.05, alpha: 0.35).cgColor]
        rl.type = .radial; rl.startPoint = CGPoint(x: 0.5, y: 0.5); rl.endPoint = CGPoint(x: 1, y: 1)
        rl.frame = redOv.bounds; redOv.layer.addSublayer(rl)
        view.addSubview(redOv)
        
        // Stamina bar
        stamBar = UIView(); stamBar.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        stamBar.layer.cornerRadius = 3; stamBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stamBar)
        stamBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -108).isActive = true
        stamBar.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stamBar.widthAnchor.constraint(equalToConstant: 140).isActive = true
        stamBar.heightAnchor.constraint(equalToConstant: 5).isActive = true
        stamFill = UIView(); stamFill.backgroundColor = UIColor(red: 0.78, green: 0.71, blue: 0.38, alpha: 1)
        stamFill.layer.cornerRadius = 3; stamBar.addSubview(stamFill)
        
        // Joystick
        joystick = JoystickView(); joystick.delegate = self
        joystick.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(joystick)
        joystick.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10).isActive = true
        joystick.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10).isActive = true
        joystick.widthAnchor.constraint(equalToConstant: 170).isActive = true
        joystick.heightAnchor.constraint(equalToConstant: 170).isActive = true
        
        // Run button — beautiful semi-transparent
        runBtn = makeBtn(title: "RUN", fontSize: 11)
        runBtn.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(runBtn)
        runBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -100).isActive = true
        runBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -25).isActive = true
        runBtn.widthAnchor.constraint(equalToConstant: 64).isActive = true
        runBtn.heightAnchor.constraint(equalToConstant: 64).isActive = true
        runBtn.addTarget(self, action: #selector(runDown), for: .touchDown)
        runBtn.addTarget(self, action: #selector(runUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        // Interact button
        interactBtn = makeBtn(title: "⬆", fontSize: 18)
        interactBtn.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(interactBtn)
        interactBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20).isActive = true
        interactBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -25).isActive = true
        interactBtn.widthAnchor.constraint(equalToConstant: 64).isActive = true
        interactBtn.heightAnchor.constraint(equalToConstant: 64).isActive = true
        interactBtn.addTarget(self, action: #selector(interactTap), for: .touchUpInside)
        
        // Prompt label
        promptLabel = UILabel()
        promptLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        promptLabel.font = UIFont(name: "Courier", size: 12)
        promptLabel.textAlignment = .center
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptLabel.isHidden = true
        view.addSubview(promptLabel)
        promptLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        promptLabel.bottomAnchor.constraint(equalTo: stamBar.topAnchor, constant: -15).isActive = true
        
        // Look gesture
        sv.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(lookPan(_:))))
    }
    
    private func makeBtn(title: String, fontSize: CGFloat) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = UIFont(name: "Courier-Bold", size: fontSize)
        b.setTitleColor(UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.6), for: .normal)
        b.backgroundColor = UIColor(white: 1, alpha: 0.06)
        b.layer.cornerRadius = 32
        b.layer.borderWidth = 1.5
        b.layer.borderColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.2).cgColor
        b.layer.shadowColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.15).cgColor
        b.layer.shadowRadius = 8
        b.layer.shadowOffset = CGSize(width: 0, height: 0)
        return b
    }
    
    private func showMenu() {
        inMenu = true
        menuOv = UIView(frame: view.bounds)
        menuOv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        menuOv.backgroundColor = UIColor(white: 0, alpha: 0.92)
        
        let title = UILabel()
        title.text = "BACKROOMS"
        title.textColor = UIColor(red: 0.78, green: 0.71, blue: 0.38, alpha: 0.9)
        title.font = UIFont(name: "Courier-Bold", size: 36)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        menuOv.addSubview(title)
        title.centerXAnchor.constraint(equalTo: menuOv.centerXAnchor).isActive = true
        title.centerYAnchor.constraint(equalTo: menuOv.centerYAnchor, constant: -60).isActive = true
        
        let sub = UILabel()
        sub.text = "Level 0"
        sub.textColor = UIColor(red: 0.78, green: 0.71, blue: 0.38, alpha: 0.4)
        sub.font = UIFont(name: "Courier", size: 14)
        sub.textAlignment = .center
        sub.translatesAutoresizingMaskIntoConstraints = false
        menuOv.addSubview(sub)
        sub.centerXAnchor.constraint(equalTo: menuOv.centerXAnchor).isActive = true
        sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8).isActive = true
        
        let play = UIButton(type: .custom)
        play.setTitle("ИГРАТЬ", for: .normal)
        play.titleLabel?.font = UIFont(name: "Courier-Bold", size: 16)
        play.setTitleColor(UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.8), for: .normal)
        play.backgroundColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.08)
        play.layer.cornerRadius = 8
        play.layer.borderWidth = 1
        play.layer.borderColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.3).cgColor
        play.translatesAutoresizingMaskIntoConstraints = false
        menuOv.addSubview(play)
        play.centerXAnchor.constraint(equalTo: menuOv.centerXAnchor).isActive = true
        play.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 40).isActive = true
        play.widthAnchor.constraint(equalToConstant: 180).isActive = true
        play.heightAnchor.constraint(equalToConstant: 50).isActive = true
        play.addTarget(self, action: #selector(startGame), for: .touchUpInside)
        
        view.addSubview(menuOv)
    }
    
    @objc private func startGame() {
        initAudio()
        UIView.animate(withDuration: 0.8, animations: {
            self.menuOv.alpha = 0
        }) { _ in
            self.menuOv.removeFromSuperview()
            self.waking = true; self.wakeT = 0
        }
    }
    
    @objc private func runDown() {
        sprinting = true
        runBtn.backgroundColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.2)
        runBtn.layer.borderColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.5).cgColor
    }
    @objc private func runUp() {
        sprinting = false
        runBtn.backgroundColor = UIColor(white: 1, alpha: 0.06)
        runBtn.layer.borderColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.2).cgColor
    }
    @objc private func interactTap() { tryInteract() }
    
    @objc private func lookPan(_ g: UIPanGestureRecognizer) {
        if g.state == .changed {
            let t = g.translation(in: view)
            yaw -= Float(t.x) * 0.004; pitch -= Float(t.y) * 0.003
            pitch = max(-1.2, min(1.2, pitch)); g.setTranslation(.zero, in: view)
        }
    }
    
    // MARK: - Loop
    @objc private func tick() {
        let now = CACurrentMediaTime()
        var dt = Float(now - lastT); lastT = now
        if dt > 0.1 { dt = 0.1 }
        
        if inMenu { return }
        
        // Wake
        if waking {
            wakeT += dt * 0.22
            if wakeT >= 1 { wakeT = 1; waking = false }
            let e = 1 - pow(1 - wakeT, 3)
            pY = 0.3 + (standY - 0.3) * e
            cam.eulerAngles.z = wakeT < 0.75 ? sin(wakeT * 14) * (1 - wakeT) * 0.04 : cam.eulerAngles.z * 0.92
        }
        
        let mm = min(1, sqrt(jX*jX + jY*jY))
        let moving = mm > 0.1
        let canSp = sprinting && stam > 0
        
        if canSp && moving { stam -= 0.4 * dt; if stam < 0 { stam = 0 } }
        else { stam += 0.18 * dt; if stam > 1 { stam = 1 } }
        if stam <= 0 { sprinting = false; runUp() }
        
        let speed = (canSp && stam > 0) ? 2.8 : 1.7
        
        if moving && !waking {
            let nx = jX/mm, ny = jY/mm
            let sy = sin(yaw), cy = cos(yaw)
            var dx = -sy*(-ny) + cy*nx
            var dz = -cy*(-ny) + (-sy)*nx
            let len: Float = sqrt(dx*dx+dz*dz)
            if len > 0 { dx /= len; dz /= len }
            let v: Float = speed * mm * dt
            let npx = cam.position.x + dx*v, npz = cam.position.z + dz*v
            if !collides(npx, cam.position.z) { cam.position.x = npx }
            if !collides(cam.position.x, npz) { cam.position.z = npz }
            
            bobT += dt * (canSp ? Float(14) : Float(9)) * mm
            bobA += ((canSp ? 0.055 : 0.028) - bobA) * 5 * dt
            shakeA += ((canSp ? 0.012 : 0.003) - shakeA) * 5 * dt
            stepClk += dt * speed * mm
            if stepClk >= (canSp ? 0.35 : 0.5) { stepClk = 0; playStep() }
        } else {
            bobA *= 1-4*dt; shakeA *= 1-4*dt; stepClk *= 0.9
        }
        
        breathClk += dt
        if breathClk >= (stam < 0.3 ? 1.5 : 3.0) { breathClk = 0; playBreath() }
        heaveA = stam < 0.12 && moving ? heaveA + (0.015-heaveA)*2*dt : heaveA*(1-4*dt)
        
        let bY = sin(bobT)*bobA, bX = cos(bobT*0.5)*bobA*0.55
        cam.position.y = pY + bY + sin(Float(CACurrentMediaTime())*1.5)*heaveA
        cam.eulerAngles.x = pitch + bX + Float.random(in:-1...1)*shakeA
        cam.eulerAngles.y = yaw + Float.random(in:-1...1)*shakeA
        
        // Stamina UI
        stamFill.frame = CGRect(x: 0, y: 0, width: stamBar.frame.width * CGFloat(stam), height: stamBar.frame.height)
        stamFill.backgroundColor = stam < 0.25 ? UIColor(red:0.55,green:0.15,blue:0.15,alpha:1) :
                                    stam < 0.5  ? UIColor(red:0.65,green:0.5,blue:0.15,alpha:1) :
                                                   UIColor(red:0.78,green:0.71,blue:0.38,alpha:1)
        let tA = stam < 0.18 ? CGFloat((1-stam*5.5)*0.5) : 0
        redOv.alpha += (tA - redOv.alpha) * CGFloat(3*dt)
        
        // Enable shadows only for 3 nearest lights
        let cp = cam.position
        for l in lts { l.light?.castsShadow = false }
        let sorted = lts.sorted { a, b in
            let da = (a.position.x-cp.x)*(a.position.x-cp.x) + (a.position.z-cp.z)*(a.position.z-cp.z)
            let db = (b.position.x-cp.x)*(b.position.x-cp.x) + (b.position.z-cp.z)*(b.position.z-cp.z)
            return da < db
        }
        for i in 0..<min(3, sorted.count) {
            sorted[i].light?.castsShadow = true
            sorted[i].light?.shadowSampleCount = 4
            sorted[i].light?.shadowRadius = 2
        }
        
        // Flicker
        for i in 0..<lts.count {
            let l = lts[i]; guard l.light!.intensity > 0 else { continue }
            if Float.random(in:0...1) < 0.003 {
                l.light!.intensity = 100; glows[i].geometry?.materials.first?.emission.intensity = 0.15
            } else if Float.random(in:0...1) < 0.01 {
                l.light!.intensity = CGFloat(600 + Float.random(in:0...600))
                glows[i].geometry?.materials.first?.emission.intensity = CGFloat(Float.random(in:0.8...1.5))
            } else {
                l.light!.intensity = CGFloat(1400 + sin(Float(CACurrentMediaTime())*0.8+Float(i)*6.1)*120)
                glows[i].geometry?.materials.first?.emission.intensity = 2.0
            }
        }
        
        // Animate doors
        for i in 0..<doors.count {
            var d = doors[i]
            let target: Float = d.open ? Float.pi/2 : 0
            d.angle += (target - d.angle) * 4 * dt
            d.node.eulerAngles.y = d.angle
            doors[i] = d
        }
        
        // Animate drawers
        for i in 0..<drawers.count {
            var dr = drawers[i]
            let target: Float = dr.open ? 0.4 : 0
            dr.offset += (target - dr.offset) * 5 * dt
            dr.node.position.z = 0.01 + dr.offset
            drawers[i] = dr
        }
        
        // Interaction prompt
        let nearDoor = doors.contains { d in
            let dp = d.node.presentation.worldPosition
            let dx = cp.x - dp.x, dz = cp.z - dp.z
            return dx*dx + dz*dz < 4.0
        }
        let nearDrawer = drawers.contains { d in
            let dp = d.node.presentation.worldPosition
            let dx = cp.x - dp.x, dz = cp.z - dp.z
            return dx*dx + dz*dz < 3.0
        }
        promptLabel.isHidden = !nearDoor && !nearDrawer
        if nearDoor { promptLabel.text = "⬆ ОТКРЫТЬ ДВЕРЬ" }
        else if nearDrawer { promptLabel.text = "⬆ ОТКРЫТЬ ЯЩИК" }
    }
}

extension GameViewController: JoystickDelegate {
    func joystickMoved(x: Float, y: Float) { jX = x; jY = y }
    func joystickReleased() { jX = 0; jY = 0 }
}
