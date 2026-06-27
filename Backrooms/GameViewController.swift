import UIKit
import SceneKit
import AVFoundation

enum StreamRoomKind {
    case normal
    case emptyLarge
    case junkPile
    case slide
    case fakeUpMaze
    case stairsStraight
    case stairsSpiral
}

struct DoorState {
    var pivot: SCNNode
    var panel: SCNNode
    var open: Bool
    var angle: Float
}

class GameViewController: UIViewController {
    
    // Scene
    private var sv: SCNView!
    private var scene: SCNScene!
    private var cam: SCNNode!
    
    // Maze
    private let cs: CGFloat = 4.0
    private let wh: CGFloat = 3.2
    // Static optimized map. No visible popping/rebuilding while the player moves.
    private let gw = 7, gh = 7
    private var maze: MazeGenerator!
    private var walls: [SCNNode] = []
    private var worldRoot = SCNNode()
    private var currentRoomX = Int.min
    private var currentRoomY = Int.min
    
    // Player
    private var pY: Float = 0.3
    private let standY: Float = 1.6
    private var yaw: Float = 0, pitch: Float = 0
    private var stam: Float = 1.0
    private var sprinting = false, waking = true, inMenu = true
    private var displayLink: CADisplayLink?
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
    private var doors: [DoorState] = []
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
    private var logOv: UIView?
    private var firstTickLogged = false
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        LatestLog.log("GameViewController viewDidLoad start")
        view.backgroundColor = .black
        loadRes()
        setupScene()
        buildLevel()
        setupUI()
        showMenu()
        LatestLog.log("GameViewController viewDidLoad done")
        lastT = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFramesPerSecond = 24
        displayLink?.isPaused = true
        displayLink?.add(to: .main, forMode: .common)
    }
    
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    
    // MARK: - Resources
    private func loadRes() {
        LatestLog.log("loadRes start")
        let b = Bundle.main
        wallImg = img("wall", b); carpImg = img("carpet", b); ceilImg = img("ceiling", b)
        lampImg = img("lamp", b); metImg = img("metal", b); woodImg = img("wood", b)
        baseImg = img("baseboard", b); colImg = img("column", b)
        LatestLog.log("loadRes done")
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
        LatestLog.log("setupScene start")
        sv = SCNView(frame: view.bounds)
        sv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sv.backgroundColor = UIColor(red: 0.78, green: 0.71, blue: 0.38, alpha: 1)
        sv.antialiasingMode = .none
        sv.preferredFramesPerSecond = 24
        sv.rendersContinuously = false
        sv.isPlaying = false
        view.addSubview(sv)
        
        scene = SCNScene(); sv.scene = scene
        scene.fogStartDistance = 1
        scene.fogEndDistance = 34
        scene.fogColor = UIColor(red: 0.78, green: 0.71, blue: 0.38, alpha: 1)
        
        cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.fieldOfView = 72
        cam.camera!.zNear = 0.05; cam.camera!.zFar = 35
        cam.camera!.wantsHDR = false
        cam.camera!.exposureOffset = 0.1
        cam.position = SCNVector3(Float(cs/2), pY, Float(cs/2))
        scene.rootNode.addChildNode(cam)
        sv.pointOfView = cam
        LatestLog.log("setupScene done")
    }
    
    // MARK: - Build / static optimized level
    private func buildLevel() {
        LatestLog.log("buildLevel static start")
        scene.rootNode.addChildNode(worldRoot)

        let al = SCNLight(); al.type = .ambient
        al.color = UIColor(red:1, green:0.98, blue:0.82, alpha:1)
        al.intensity = 170
        let an = SCNNode(); an.light = al; worldRoot.addChildNode(an)

        for y in 0..<gh {
            for x in 0..<gw {
                buildRoom(x: x, y: y, centerX: 0, centerY: 0)
            }
        }
        LatestLog.log("buildLevel static done rooms=\(gw*gh) nodes=\(worldRoot.childNodes.count)")
    }

    private func roomCoord() -> (Int, Int) {
        let rx = Int(floor(cam.position.x / Float(cs)))
        let ry = Int(floor(cam.position.z / Float(cs)))
        return (rx, ry)
    }

    private func rebuildActiveRoomsIfNeeded() { }

    private func buildRoom(x: Int, y: Int, centerX: Int, centerY: Int) {
        let kind = roomKind(x, y)
        let special = specialTypeForRoom(x, y)
        let wM = mat(forType: special, base: mat(wallImg, 2, 1))
        let fM = mat(carpImg, 3, 3)
        let cM = mat(ceilImg, 2, 2)
        let mM = mat(metImg)
        let bM = mat(baseImg)
        let coM = mat(colImg)
        let wdM = mat(woodImg)
        let drM = wdM

        let ox = CGFloat(x) * cs
        let oz = CGFloat(y) * cs
        let cx = ox + cs/2
        let cz = oz + cs/2

        let fg = SCNBox(width: cs, height: 0.02, length: cs, chamferRadius: 0)
        fg.materials = [fM]
        let fn = SCNNode(geometry: fg); fn.position = SCNVector3(Float(cx), Float(-0.01), Float(cz))
        worldRoot.addChildNode(fn)

        if kind != .fakeUpMaze {
            let cg = SCNBox(width: cs, height: 0.05, length: cs, chamferRadius: 0)
            cg.materials = [cM]
            let cn = SCNNode(geometry: cg); cn.position = SCNVector3(Float(cx), Float(wh), Float(cz))
            worldRoot.addChildNode(cn)
        }

        addWallWithGap(horizontal: true, x: cx, z: oz, m: wM, base: bM)
        addWallWithGap(horizontal: false, x: ox, z: cz, m: wM, base: bM)
        if x == gw - 1 { addWallWithGap(horizontal: false, x: ox + cs, z: cz, m: wM, base: bM) }
        if y == gh - 1 { addWallWithGap(horizontal: true, x: cx, z: oz + cs, m: wM, base: bM) }

        if hash01(x, y, 10) < 0.28 { addLamp(x: cx, z: cz, broken: hash01(x,y,11) < 0.12 || special == .dark, special: special) }

        if kind == .emptyLarge {
            addLargeEmptyRoomHints(cx: cx, cz: cz, m: coM)
        } else if kind == .junkPile {
            addJunkPile(cx: cx, cz: cz, m: wdM, metal: mM, seedX: x, seedY: y)
        } else if kind == .slide {
            addSlidePassage(cx: cx, cz: cz, m: mM, seedX: x, seedY: y)
        } else if kind == .fakeUpMaze {
            addFakeUpMaze(cx: cx, cz: cz, wall: wM, floor: cM, seedX: x, seedY: y)
        } else if kind == .stairsStraight {
            addStraightStairs(cx: cx, cz: cz, m: wdM, seedX: x, seedY: y)
        } else if kind == .stairsSpiral {
            addSpiralStairs(cx: cx, cz: cz, m: wdM)
        }

        if kind != .emptyLarge && hash01(x, y, 20) < 0.25 {
            let colG = SCNBox(width: 0.28, height: wh, length: 0.28, chamferRadius: 0)
            colG.materials = [coM]
            let col = SCNNode(geometry: colG)
            col.position = SCNVector3(Float(cx + jitter(x,y,21)*0.8), Float(wh/2), Float(cz + jitter(x,y,22)*0.8))
            worldRoot.addChildNode(col); walls.append(col)
        }

        if kind == .normal || kind == .fakeUpMaze {
            if hash01(x, y, 30) < 0.10 { addTable(x: cx + jitter(x,y,31)*0.7, z: cz + jitter(x,y,32)*0.7, m: wdM) }
            if hash01(x, y, 40) < 0.06 { addCabinet(x: cx + jitter(x,y,41)*0.7, z: cz + jitter(x,y,42)*0.7, m: wdM) }
        }
        if kind != .slide && hash01(x, y, 50) < 0.08 { addDoor(x: cx, z: oz + 0.08, m: drM, axis: 0) }

        if hash01(x, y, 60) < 0.18 {
            let pg = SCNCylinder(radius: 0.035, height: cs); pg.materials = [mM]
            let p = SCNNode(geometry: pg)
            p.eulerAngles = SCNVector3(0, 0, Float.pi/2)
            p.position = SCNVector3(Float(cx), Float(wh-0.12), Float(cz))
            worldRoot.addChildNode(p)
        }
    }

    private func addWallWithGap(horizontal: Bool, x: CGFloat, z: CGFloat, m: SCNMaterial, base: SCNMaterial) {
        let gap: CGFloat = 1.05
        let seg = (cs - gap) / 2
        if horizontal {
            let g = SCNBox(width: seg, height: wh, length: 0.12, chamferRadius: 0)
            addW(g, m, x - (gap/2 + seg/2), wh/2, z)
            addW(g, m, x + (gap/2 + seg/2), wh/2, z)
            let bg = SCNBox(width: seg, height: 0.12, length: 0.06, chamferRadius: 0)
            addB(bg, base, x - (gap/2 + seg/2), 0.06, z)
            addB(bg, base, x + (gap/2 + seg/2), 0.06, z)
        } else {
            let g = SCNBox(width: 0.12, height: wh, length: seg, chamferRadius: 0)
            addW(g, m, x, wh/2, z - (gap/2 + seg/2))
            addW(g, m, x, wh/2, z + (gap/2 + seg/2))
            let bg = SCNBox(width: 0.06, height: 0.12, length: seg, chamferRadius: 0)
            addB(bg, base, x, 0.06, z - (gap/2 + seg/2))
            addB(bg, base, x, 0.06, z + (gap/2 + seg/2))
        }
    }

    private func roomKind(_ x: Int, _ y: Int) -> StreamRoomKind {
        // Rare special rooms, so the level does not look like furniture spam.
        let v = hash01(x, y, 7)
        if v < 0.08 { return .emptyLarge }
        if v < 0.12 { return .junkPile }
        if v < 0.15 { return .slide }
        if v < 0.18 { return .fakeUpMaze }
        if v < 0.21 { return .stairsStraight }
        if v < 0.23 { return .stairsSpiral }
        return .normal
    }

    private func slideDirection(_ x: Int, _ y: Int) -> SCNVector3 {
        let n = Int(hash01(x, y, 77) * 4)
        switch n {
        case 0: return SCNVector3(1, 0, 0)
        case 1: return SCNVector3(-1, 0, 0)
        case 2: return SCNVector3(0, 0, 1)
        default: return SCNVector3(0, 0, -1)
        }
    }

    private func addLargeEmptyRoomHints(cx: CGFloat, cz: CGFloat, m: SCNMaterial) {
        // A big empty room illusion: sparse corner columns and a darker wide center.
        for (dx, dz) in [(-1.45,-1.45),(1.45,-1.45),(-1.45,1.45),(1.45,1.45)] {
            let g = SCNBox(width: 0.16, height: wh, length: 0.16, chamferRadius: 0)
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float(cx + CGFloat(dx)), Float(wh/2), Float(cz + CGFloat(dz)))
            worldRoot.addChildNode(n); walls.append(n)
        }
    }

    private func addJunkPile(cx: CGFloat, cz: CGFloat, m: SCNMaterial, metal: SCNMaterial, seedX: Int, seedY: Int) {
        for i in 0..<5 {
            let w = CGFloat(Float(0.25) + hash01(seedX, seedY, 100+i) * Float(0.45))
            let h = CGFloat(Float(0.18) + hash01(seedX, seedY, 130+i) * Float(0.55))
            let d = CGFloat(Float(0.25) + hash01(seedX, seedY, 160+i) * Float(0.45))
            let g = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
            g.materials = [(i % 3 == 0) ? metal : m]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float(cx + jitter(seedX, seedY, 200+i) * 1.05), Float(h/2), Float(cz + jitter(seedX, seedY, 240+i) * 1.05))
            n.eulerAngles.y = Float(hash01(seedX, seedY, 280+i) * Float.pi)
            worldRoot.addChildNode(n); walls.append(n)
        }
    }

    private func addSlidePassage(cx: CGFloat, cz: CGFloat, m: SCNMaterial, seedX: Int, seedY: Int) {
        let dir = slideDirection(seedX, seedY)
        let g = SCNBox(width: 1.45, height: 0.08, length: 3.2, chamferRadius: 0)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(Float(cx), Float(0.18), Float(cz))
        if abs(dir.x) > 0 { n.eulerAngles.y = Float.pi/2 }
        n.eulerAngles.x = (dir.z >= 0 || dir.x >= 0) ? Float(-0.28) : Float(0.28)
        worldRoot.addChildNode(n)
    }

    private func addFakeUpMaze(cx: CGFloat, cz: CGFloat, wall: SCNMaterial, floor: SCNMaterial, seedX: Int, seedY: Int) {
        let deck = SCNBox(width: cs * 0.92, height: 0.04, length: cs * 0.92, chamferRadius: 0)
        deck.materials = [floor]
        let dn = SCNNode(geometry: deck)
        dn.position = SCNVector3(Float(cx), Float(wh + 2.2), Float(cz))
        worldRoot.addChildNode(dn)
        for i in 0..<6 {
            let horizontal = i % 2 == 0
            let g = SCNBox(width: horizontal ? 2.1 : 0.09, height: 1.1, length: horizontal ? 0.09 : 2.1, chamferRadius: 0)
            g.materials = [wall]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float(cx + jitter(seedX, seedY, 310+i)*1.15), Float(wh + 2.75), Float(cz + jitter(seedX, seedY, 340+i)*1.15))
            worldRoot.addChildNode(n)
        }
    }

    private func addStraightStairs(cx: CGFloat, cz: CGFloat, m: SCNMaterial, seedX: Int, seedY: Int) {
        let dir = slideDirection(seedX, seedY)
        for i in 0..<7 {
            let g = SCNBox(width: 1.15, height: 0.12, length: 0.42, chamferRadius: 0)
            g.materials = [m]
            let n = SCNNode(geometry: g)
            let off = CGFloat(i) * 0.34 - 1.05
            n.position = SCNVector3(Float(cx + CGFloat(dir.x) * off), Float(0.08 + CGFloat(i) * 0.12), Float(cz + CGFloat(dir.z) * off))
            if abs(dir.x) > 0 { n.eulerAngles.y = Float.pi/2 }
            worldRoot.addChildNode(n)
        }
    }

    private func addSpiralStairs(cx: CGFloat, cz: CGFloat, m: SCNMaterial) {
        let poleG = SCNCylinder(radius: 0.045, height: 2.6); poleG.materials = [m]
        let pole = SCNNode(geometry: poleG); pole.position = SCNVector3(Float(cx), Float(1.3), Float(cz))
        worldRoot.addChildNode(pole)
        for i in 0..<5 {
            let g = SCNBox(width: 0.85, height: 0.08, length: 0.28, chamferRadius: 0)
            g.materials = [m]
            let n = SCNNode(geometry: g)
            let a = Float(i) * 0.65
            n.position = SCNVector3(Float(cx) + cos(a) * Float(0.55), Float(0.15) + Float(i) * Float(0.14), Float(cz) + sin(a) * Float(0.55))
            n.eulerAngles.y = -a
            worldRoot.addChildNode(n)
        }
    }

    private func specialTypeForRoom(_ x: Int, _ y: Int) -> SpecialType {
        let v = hash01(x, y, 99)
        if v < 0.04 { return .red }
        if v < 0.08 { return .dark }
        if v < 0.12 { return .flooded }
        return .none
    }

    private func hash01(_ x: Int, _ y: Int, _ salt: Int) -> Float {
        // Important: do not convert the mixed value to Int32.
        // Some salts are large and Int32(...) traps on iOS, causing a black-screen crash during buildLevel().
        var n = UInt64(bitPattern: Int64(x)) &* 73_856_093
        n ^= UInt64(bitPattern: Int64(y)) &* 19_349_663
        n ^= UInt64(bitPattern: Int64(salt)) &* 83_492_791
        n ^= n << 13
        n ^= n >> 7
        n ^= n << 17
        return Float(n % 10_000) / Float(10_000)
    }

    private func jitter(_ x: Int, _ y: Int, _ salt: Int) -> CGFloat {
        return CGFloat(hash01(x, y, salt) * Float(2) - Float(1))
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
        let mMat = colorMat(UIColor.darkGray)
        // Housing
        let hg = SCNBox(width: 1.3, height: 0.06, length: 0.35, chamferRadius: 0); hg.materials = [mMat]
        let h = SCNNode(geometry: hg); h.position = SCNVector3(Float(x), Float(wh-0.03), Float(z))
        worldRoot.addChildNode(h)
        // End caps
        for sx: CGFloat in [-0.65, 0.65] {
            let cg = SCNBox(width: 0.06, height: 0.08, length: 0.35, chamferRadius: 0); cg.materials = [mMat]
            let c = SCNNode(geometry: cg); c.position = SCNVector3(Float(x+sx), Float(wh-0.04), Float(z))
            worldRoot.addChildNode(c)
        }
        // Wires
        for sx: CGFloat in [-0.4, 0.4] {
            let wg = SCNCylinder(radius: 0.008, height: 0.15); wg.materials = [mMat]
            let w = SCNNode(geometry: wg); w.position = SCNVector3(Float(x+sx), Float(wh-0.1), Float(z))
            worldRoot.addChildNode(w)
        }
        // Tube
        let tg = SCNBox(width: 1.15, height: 0.02, length: 0.26, chamferRadius: 0)
        let tMat = SCNMaterial()
        tMat.emission.contents = UIColor(white: 1.0, alpha: 1.0)
        tMat.emission.intensity = broken ? 0.05 : 2.0
        tMat.diffuse.contents = UIColor(white: 1, alpha: 0.9)
        tMat.isDoubleSided = true
        tg.materials = [tMat]
        let t = SCNNode(geometry: tg); t.position = SCNVector3(Float(x), Float(wh-0.07), Float(z))
        worldRoot.addChildNode(t); glows.append(t)
        
        // Transparent cone meshes were a big GPU cost on iPhone, so they are disabled.
        
        // Point light — no dynamic shadows for stability/performance
        let l = SCNLight()
        l.type = .omni
        let lColor: UIColor
        switch special {
        case .red: lColor = UIColor(red: 1, green: 0.6, blue: 0.5, alpha: 1)
        case .flooded: lColor = UIColor(red: 0.9, green: 1, blue: 0.85, alpha: 1)
        default: lColor = UIColor(red: 1, green: 0.99, blue: 0.88, alpha: 1)
        }
        l.color = lColor
        l.intensity = broken ? 0 : 520
        l.attenuationStartDistance = 0.5
        l.attenuationEndDistance = 7
        l.attenuationFalloffExponent = 2
        l.castsShadow = false // Performance! Will enable for nearest only
        let ln = SCNNode(); ln.light = l
        ln.position = SCNVector3(Float(x), Float(wh-0.25), Float(z))
        worldRoot.addChildNode(ln); lts.append(ln)
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
        worldRoot.addChildNode(p)
    }
    
    // Cabinet with interactable drawers
    private func addCabinet(x: CGFloat, z: CGFloat, m: SCNMaterial) {
        let p = SCNNode(); p.position = SCNVector3(Float(x), 0, Float(z))
        p.eulerAngles.y = Float.random(in: 0...Float.pi)
        let bg = SCNBox(width: 0.5, height: 1.3, length: 0.4, chamferRadius: 0)
        bg.materials = [m]; let bn = SCNNode(geometry: bg); bn.position = SCNVector3(0, 0.65, 0)
        p.addChildNode(bn); walls.append(bn)
        // Drawer handles
        let hM = colorMat(UIColor.darkGray); hM.metalness.contents = UIColor(white: 0.8, alpha: 1)
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
        worldRoot.addChildNode(p)
    }
    
    // Door with a real hinge pivot. Opens sideways instead of spinning around the center.
    private func addDoor(x: CGFloat, z: CGFloat, m: SCNMaterial, axis: Float) {
        let pivot = SCNNode()
        pivot.position = SCNVector3(Float(x - 0.45), 1.1, Float(z))
        pivot.name = "doorPivot"

        let dg = SCNBox(width: 0.9, height: 2.15, length: 0.055, chamferRadius: 0)
        dg.materials = [m]
        let panel = SCNNode(geometry: dg)
        panel.position = SCNVector3(0.45, 0, 0)
        panel.name = "door"
        pivot.addChildNode(panel)

        let hg = SCNBox(width: 0.06, height: 0.12, length: 0.08, chamferRadius: 0)
        let hM = colorMat(UIColor.darkGray); hM.metalness.contents = UIColor(white: 0.8, alpha: 1)
        hg.materials = [hM]
        let hn = SCNNode(geometry: hg); hn.position = SCNVector3(0.72, 0, 0.055)
        panel.addChildNode(hn)

        worldRoot.addChildNode(pivot)
        doors.append(DoorState(pivot: pivot, panel: panel, open: false, angle: 0))
        // Keep closed doors in collision list; remove them when open in collides().
        walls.append(panel)
    }
    
    private func addW(_ geo: SCNGeometry, _ m: SCNMaterial, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        let n = SCNNode(geometry: geo); n.geometry?.materials = [m]
        n.position = SCNVector3(Float(x), Float(y), Float(z))
        worldRoot.addChildNode(n); walls.append(n)
    }
    private func addB(_ geo: SCNGeometry, _ m: SCNMaterial, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        let n = SCNNode(geometry: geo); n.geometry?.materials = [m]
        n.position = SCNVector3(Float(x), Float(y), Float(z)); worldRoot.addChildNode(n)
    }
    private func mat(_ img: UIImage, _ rx: Int = 1, _ ry: Int = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = img; m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(rx), Float(ry), 1)
        m.roughness.contents = UIColor(white: 0.85, alpha: 1); m.locksAmbientWithDiffuse = true
        return m
    }
    private func colorMat(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.roughness.contents = UIColor(white: 0.9, alpha: 1)
        m.locksAmbientWithDiffuse = true
        return m
    }
    
    // MARK: - Collision
    private func collides(_ nx: Float, _ nz: Float) -> Bool {
        for w in walls {
            if doors.contains(where: { $0.open && $0.panel === w }) { continue }
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
            let dp = d.panel.presentation.worldPosition
            let dx = pos.x - dp.x, dz = pos.z - dp.z
            if dx*dx + dz*dz < 3.2 {
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
        
        let logBtn = UIButton(type: .custom)
        logBtn.setTitle("LATESTLOG", for: .normal)
        logBtn.titleLabel?.font = UIFont(name: "Courier", size: 12)
        logBtn.setTitleColor(UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.55), for: .normal)
        logBtn.backgroundColor = UIColor(white: 1, alpha: 0.04)
        logBtn.layer.cornerRadius = 6
        logBtn.layer.borderWidth = 1
        logBtn.layer.borderColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 0.18).cgColor
        logBtn.translatesAutoresizingMaskIntoConstraints = false
        menuOv.addSubview(logBtn)
        logBtn.centerXAnchor.constraint(equalTo: menuOv.centerXAnchor).isActive = true
        logBtn.topAnchor.constraint(equalTo: play.bottomAnchor, constant: 12).isActive = true
        logBtn.widthAnchor.constraint(equalToConstant: 140).isActive = true
        logBtn.heightAnchor.constraint(equalToConstant: 34).isActive = true
        logBtn.addTarget(self, action: #selector(showLatestLog), for: .touchUpInside)
        
        view.addSubview(menuOv)
    }
    
    @objc private func showLatestLog() {
        let vc = UIViewController()
        vc.view.backgroundColor = .black
        let tv = UITextView(frame: vc.view.bounds)
        tv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tv.backgroundColor = .black
        tv.textColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 1)
        tv.font = UIFont(name: "Menlo", size: 11) ?? UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.isEditable = false
        tv.text = LatestLog.text()
        vc.view.addSubview(tv)
        let close = UIButton(type: .system)
        close.setTitle("Закрыть", for: .normal)
        close.tintColor = UIColor(red: 0.9, green: 0.82, blue: 0.45, alpha: 1)
        close.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        close.frame = CGRect(x: 12, y: 12, width: 100, height: 36)
        close.layer.cornerRadius = 8
        close.addAction(UIAction { [weak vc] _ in vc?.dismiss(animated: true) }, for: .touchUpInside)
        vc.view.addSubview(close)
        present(vc, animated: true)
    }
    
    @objc private func startGame() {
        LatestLog.log("startGame tapped")
        inMenu = false
        displayLink?.isPaused = false
        sv.isPlaying = true
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
    
    private func handleRoomEffects(dt: Float) {
        let (rx, ry) = roomCoord()
        let kind = roomKind(rx, ry)
        if kind == .slide && !waking {
            let dir = slideDirection(rx, ry)
            let force: Float = 4.8 * dt
            cam.position.x += dir.x * force
            cam.position.z += dir.z * force
            pY += (0.72 - pY) * min(1, dt * 4)
            pitch += (0.28 - pitch) * min(1, dt * 2)
            heaveA = max(heaveA, 0.012)
            promptLabel.isHidden = false
            promptLabel.text = "СКОЛЬЖЕНИЕ ВНИЗ — НАЗАД НЕ ПОДНЯТЬСЯ"
        }
    }

    // MARK: - Loop
    @objc private func tick() {
        let now = CACurrentMediaTime()
        var dt = Float(now - lastT); lastT = now
        if dt > 0.1 { dt = 0.1 }
        
        if inMenu { return }
        if !firstTickLogged { firstTickLogged = true; LatestLog.log("first gameplay tick") }
        
        // Wake
        if waking {
            wakeT += dt * 0.22
            if wakeT >= 1 { wakeT = 1; waking = false }
            let e = 1 - pow(1 - wakeT, 3)
            pY = 0.3 + (standY - 0.3) * e
            cam.eulerAngles.z = wakeT < 0.75 ? sin(wakeT * 14) * (1 - wakeT) * 0.04 : cam.eulerAngles.z * 0.92
        }
        
        let mm: Float = min(Float(1), (jX*jX + jY*jY).squareRoot())
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
            let len: Float = (dx*dx + dz*dz).squareRoot()
            if len > 0 { dx /= len; dz /= len }
            let v: Float = Float(speed) * Float(mm) * Float(dt)
            let npx = cam.position.x + dx * v
            let npz = cam.position.z + dz * v
            if !collides(npx, cam.position.z) { cam.position.x = npx }
            if !collides(cam.position.x, npz) { cam.position.z = npz }
            
            bobT += dt * (canSp ? Float(14) : Float(9)) * mm
            bobA += ((canSp ? Float(0.055) : Float(0.028)) - bobA) * Float(5) * dt
            shakeA += ((canSp ? Float(0.012) : Float(0.003)) - shakeA) * Float(5) * dt
            stepClk += Float(dt) * Float(speed) * Float(mm)
            if stepClk >= (canSp ? Float(0.35) : Float(0.5)) { stepClk = 0; playStep() }
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
        
        handleRoomEffects(dt: dt)
        
        // Stamina UI
        stamFill.frame = CGRect(x: 0, y: 0, width: stamBar.frame.width * CGFloat(stam), height: stamBar.frame.height)
        stamFill.backgroundColor = stam < 0.25 ? UIColor(red:0.55,green:0.15,blue:0.15,alpha:1) :
                                    stam < 0.5  ? UIColor(red:0.65,green:0.5,blue:0.15,alpha:1) :
                                                   UIColor(red:0.78,green:0.71,blue:0.38,alpha:1)
        let tA = stam < 0.18 ? CGFloat((1-stam*5.5)*0.5) : 0
        redOv.alpha += (tA - redOv.alpha) * CGFloat(3*dt)
        
        // Keep dynamic shadows disabled; enabling them every frame can crash/kill the app on phones.
        let cp = cam.position
        
        // Flicker
        for i in 0..<lts.count {
            let l = lts[i]; guard l.light!.intensity > 0 else { continue }
            if Float.random(in:0...1) < 0.003 {
                l.light!.intensity = 100; glows[i].geometry?.materials.first?.emission.intensity = 0.15
            } else if Float.random(in:0...1) < 0.01 {
                l.light!.intensity = CGFloat(320 + Float.random(in:0...220))
                glows[i].geometry?.materials.first?.emission.intensity = CGFloat(Float.random(in:0.8...1.5))
            } else {
                l.light!.intensity = CGFloat(520 + sin(Float(CACurrentMediaTime())*0.8+Float(i)*6.1)*35)
                glows[i].geometry?.materials.first?.emission.intensity = 2.0
            }
        }
        
        // Animate doors
        for i in 0..<doors.count {
            var d = doors[i]
            let target: Float = d.open ? -Float.pi/2 : 0
            d.angle += (target - d.angle) * 5 * dt
            d.pivot.eulerAngles.y = d.angle
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
            let dp = d.panel.presentation.worldPosition
            let dx = cp.x - dp.x, dz = cp.z - dp.z
            return dx*dx + dz*dz < 3.2
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
