import Foundation

struct MazeCell {
    var north = true, south = true, east = true, west = true
    var visited = false
    var isSpecial = false
    var specialType: SpecialType = .none
}

enum SpecialType { case none, dark, red, flooded }

class MazeGenerator {
    let w: Int, h: Int
    var grid: [[MazeCell]]
    
    init(width: Int, height: Int) {
        self.w = width; self.h = height
        grid = Array(repeating: Array(repeating: MazeCell(), count: width), count: height)
    }
    
    func generate() {
        var stk: [(Int,Int)] = []
        var cx = 0, cy = 0
        grid[cy][cx].visited = true
        
        while true {
            let ns = nb(cx, cy)
            if !ns.isEmpty {
                let (nx, ny, d) = ns.randomElement()!
                stk.append((cx, cy))
                remWall(&grid[cy][cx], &grid[ny][nx], d)
                cx = nx; cy = ny; grid[cy][cx].visited = true
            } else if !stk.isEmpty {
                let p = stk.removeLast(); cx = p.0; cy = p.1
            } else { break }
        }
        
        // Open walls for Backrooms feel
        for y in 0..<h { for x in 0..<w {
            if Bool.random() {
                let dirs: [(Int,Int,String)] = [(0,-1,"N"),(0,1,"S"),(1,0,"E"),(-1,0,"W")]
                if let (dx,dy,d) = dirs.randomElement() {
                    let nx = x+dx, ny = y+dy
                    if nx>=0 && nx<w && ny>=0 && ny<h { remWall(&grid[y][x], &grid[ny][nx], d) }
                }
            }
        }}
        
        // Special rooms. Keep indices inside the current maze size.
        let specials: [(Int,SpecialType)] = [(2,.dark), (4,.red), (6,.flooded)]
        for (idx, st) in specials {
            guard h > 2, w > 3 else { continue }
            let sy = min(max(idx, 0), h - 1)
            let sx = min(max(w - 3, 0), w - 1)
            grid[sy][sx].isSpecial = true
            grid[sy][sx].specialType = st
            // Open all internal walls in special room
            grid[sy][sx].north = false; grid[sy][sx].south = false
            grid[sy][sx].east = false; grid[sy][sx].west = false
        }
    }
    
    private func nb(_ x: Int, _ y: Int) -> [(Int,Int,String)] {
        var r: [(Int,Int,String)] = []
        if y>0 && !grid[y-1][x].visited { r.append((x,y-1,"N")) }
        if y<h-1 && !grid[y+1][x].visited { r.append((x,y+1,"S")) }
        if x<w-1 && !grid[y][x+1].visited { r.append((x+1,y,"E")) }
        if x>0 && !grid[y][x-1].visited { r.append((x-1,y,"W")) }
        return r
    }
    
    private func remWall(_ a: inout MazeCell, _ b: inout MazeCell, _ d: String) {
        switch d {
        case "N": a.north = false; b.south = false
        case "S": a.south = false; b.north = false
        case "E": a.east = false; b.west = false
        case "W": a.west = false; b.east = false
        default: break
        }
    }
}
