extension PNG.Data.Rectangular 
{
    func collect<C>(scanline:inout C, at base:(x:Int, y:Int), stride:Int)
        where   C:RandomAccessCollection & MutableCollection, 
                C.Index == Int, C.Element == UInt8
    {
        let indices:EnumeratedSequence<StrideTo<Int>> = 
            Swift.stride(from: base.x, to: self.size.x, by: stride).enumerated()
        switch self.layout.format 
        {
        // 0 x 1 
        case .v1, .indexed1:
            // need to initialize to 0 since we are using |=
            for a:Int in scanline.indices 
            {
                scanline[a] = 0
            }
            for (i, x):(Int, Int) in indices
            {
                let a:Int    =   i >> 3 &+ scanline.startIndex, 
                    b:Int    =  ~i & 0b111
                scanline[a] |= (self.storage[base.y &* self.size.x &+ x] & 0b0001) &<< b 
            }
        
        case .v2, .indexed2:
            for a:Int in scanline.indices 
            {
                scanline[a] = 0
            }
            for (i, x):(Int, Int) in indices
            {
                let a:Int    =   i >> 2 &+ scanline.startIndex, 
                    b:Int    = (~i & 0b011) << 1
                scanline[a] |= (self.storage[base.y &* self.size.x &+ x] & 0b0011) &<< b 
            }
        
        case .v4, .indexed4:
            for a:Int in scanline.indices 
            {
                scanline[a] = 0
            }
            for (i, x):(Int, Int) in indices
            {
                let a:Int    =   i >> 1 &+ scanline.startIndex, 
                    b:Int    = (~i & 0b001) << 2
                scanline[a] |= (self.storage[base.y &* self.size.x &+ x] & 0b1111) &<< b
            }
        
        // 1 x 1
        case .v8, .indexed8:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = i &+ scanline.startIndex, 
                    d:Int = base.y &* self.size.x &+ x
                scanline[a] = self.storage[d]
            }
        // 1 x 2, 2 x 1
        case .va8, .v16:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 2 &* i &+ scanline.startIndex, 
                    d:Int = 2 &* (base.y &* self.size.x &+ x)
                scanline[a     ] = self.storage[d     ]
                scanline[a &+ 1] = self.storage[d &+ 1]
            }
        // 1 x 3
        case .rgb8, .bgr8:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 3 &* i &+ scanline.startIndex, 
                    d:Int = 3 &* (base.y &* self.size.x &+ x)
                scanline[a     ] = self.storage[d     ]
                scanline[a &+ 1] = self.storage[d &+ 1]
                scanline[a &+ 2] = self.storage[d &+ 2]
            }
        // 1 x 4, 2 x 2
        case .rgba8, .bgra8, .va16:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 4 &* i &+ scanline.startIndex, 
                    d:Int = 4 &* (base.y &* self.size.x &+ x)
                scanline[a     ] = self.storage[d     ]
                scanline[a &+ 1] = self.storage[d &+ 1]
                scanline[a &+ 2] = self.storage[d &+ 2]
                scanline[a &+ 3] = self.storage[d &+ 3]
            }
        // 2 x 3
        case .rgb16:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 6 &* i &+ scanline.startIndex, 
                    d:Int = 6 &* (base.y &* self.size.x &+ x)
                scanline[a     ] = self.storage[d     ]
                scanline[a &+ 1] = self.storage[d &+ 1]
                scanline[a &+ 2] = self.storage[d &+ 2]
                scanline[a &+ 3] = self.storage[d &+ 3]
                scanline[a &+ 4] = self.storage[d &+ 4]
                scanline[a &+ 5] = self.storage[d &+ 5]
            }
        // 2 x 4
        case .rgba16:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 8 &* i &+ scanline.startIndex, 
                    d:Int = 8 &* (base.y &* self.size.x &+ x)
                scanline[a     ] = self.storage[d     ]
                scanline[a &+ 1] = self.storage[d &+ 1]
                scanline[a &+ 2] = self.storage[d &+ 2]
                scanline[a &+ 3] = self.storage[d &+ 3]
                scanline[a &+ 4] = self.storage[d &+ 4]
                scanline[a &+ 5] = self.storage[d &+ 5]
                scanline[a &+ 6] = self.storage[d &+ 6]
                scanline[a &+ 7] = self.storage[d &+ 7]
            }
        }
    }
}

extension PNG 
{
    struct Encoder 
    {
        enum Pass 
        {
            case subimage(Int)
            case image
        }
        
        private 
        var row:(index:Int, reference:[UInt8])?, 
            pass:Pass?
        private 
        var deflator:LZ77.Deflator 
    }
}
extension PNG.Encoder 
{
    init(interlaced:Bool, level:Int, hint:Int = 1 << 15)
    {
        self.row        = nil
        self.pass       = interlaced ? .subimage(0) : .image
        self.deflator   = .init(level: level, hint: hint)
    }
    
    mutating 
    func pull(size:(x:Int, y:Int), pixel:PNG.Format.Pixel, 
        delegate:(inout UnsafeMutableBufferPointer<UInt8>, (x:Int, y:Int), Int) throws -> ()) 
        rethrows -> [UInt8]?
    {
        let delay:Int   = (pixel.volume + 7) >> 3
        switch self.pass 
        {
        case .subimage(let pass)?:
            for z:Int in pass ..< 7
            {
                let (base, exponent):((x:Int, y:Int), (x:Int, y:Int)) = PNG.adam7[z]
                let stride:(x:Int, y:Int)   = 
                (
                    x: 1                                 << exponent.x, 
                    y: 1                                 << exponent.y
                )
                let subimage:(x:Int, y:Int) = 
                (
                    x: (size.x + stride.x - base.x - 1 ) >> exponent.x, 
                    y: (size.y + stride.y - base.y - 1 ) >> exponent.y
                )
                
                guard subimage.x > 0, subimage.y > 0 
                else 
                {
                    continue 
                }
                
                let pitch:Int = (subimage.x * pixel.volume + 7) >> 3
                var (start, last):(Int, [UInt8]) = self.row ?? 
                    (0, .init(repeating: 0, count: pitch + 1))
                self.row = nil 
                for y:Int in start ..< subimage.y 
                {
                    if let data:[UInt8] = self.deflator.pop() 
                    {
                        self.row  = (y, last) 
                        self.pass = .subimage(z)
                        return data 
                    }
                    // filter byte is initialized to 0
                    let scanline:[UInt8] = 
                        try .init(unsafeUninitializedCapacity: last.count) 
                    {
                        $0.baseAddress?.initialize(to: 0)
                        var tail:UnsafeMutableBufferPointer<UInt8> = 
                            .init(rebasing: $0.dropFirst())
                        try delegate(&tail, (base.x, base.y + y * stride.y), stride.x)
                        $1 = last.count
                    }
                    
                    self.deflator.push(Self.filter(scanline, last: last, delay: delay))
                    last = scanline 
                }
            }
            
            self.deflator.push([], last: true)
            self.pass = nil
        
        case .image?:
            let pitch:Int = (size.x * pixel.volume + 7) >> 3
            
            var (start, last):(Int, [UInt8]) = self.row ?? 
                (0, .init(repeating: 0, count: pitch + 1))
            self.row = nil 
            for y:Int in start ..< size.y 
            {
                if let data:[UInt8] = self.deflator.pop() 
                {
                    self.row  = (y, last) 
                    return data 
                }
                
                let scanline:[UInt8] = 
                    try .init(unsafeUninitializedCapacity: last.count) 
                {
                    $0.baseAddress?.initialize(to: 0)
                    var tail:UnsafeMutableBufferPointer<UInt8> = 
                        .init(rebasing: $0.dropFirst())
                    try delegate(&tail, (0, y), 1)
                    $1 = last.count
                }
                
                self.deflator.push(Self.filter(scanline, last: last, delay: delay))
                last = scanline 
            }
            
            self.deflator.push([], last: true)
            self.pass = nil
        
        case nil:
            break 
        }
        
        let data:[UInt8] = self.deflator.pull() 
        return data.isEmpty ? nil : data
    }
    
    static 
    func filter(_ line:[UInt8], last:[UInt8], delay:Int) -> [UInt8]
    {
        //  filtering can be done in parallel
        //  c b
        //  a x
        let current:ArraySlice<UInt8>   = line.dropFirst(), 
            last:ArraySlice<UInt8>      = last.dropFirst()
        let candidates:([UInt8], [UInt8], [UInt8], [UInt8], [UInt8]) =
        (
            line,
            [1] +     current.prefix   (delay) 
                + zip(current.dropFirst(delay),     current).map
            {
                (e:(x:UInt8,    a:UInt8) ) -> UInt8 in 
                e.x &- e.a
            },
            [2] + zip(current,                                   last).map
            {
                (e:(x:UInt8,                b:UInt8) ) -> UInt8 in 
                e.x &- e.b
            },
            [3] + zip(current.prefix   (delay),                  last.prefix   (delay) ).map
            {
                (e:(x:UInt8,                b:UInt8) ) -> UInt8 in 
                e.x &- e.b >> 1
            } 
                + zip(current.dropFirst(delay), zip(current,     last.dropFirst(delay))).map
            {
                (e:(x:UInt8, y:(a:UInt8,    b:UInt8))) -> UInt8 in
                e.x &- UInt8.init((UInt16.init(e.y.a) &+ UInt16.init(e.y.b)) >> 1)
            },
            [4] + zip(current.prefix   (delay),                  last.prefix   (delay) ).map
            {
                (e:(x:UInt8,                b:UInt8) ) -> UInt8 in 
                e.x &- PNG.paeth(0, e.b, 0)
            }
                + zip(current.dropFirst(delay), zip(current, zip(last.dropFirst(delay), last))).map
            {
                (e:(x:UInt8, y:(a:UInt8, z:(b:UInt8, c:UInt8)))) -> UInt8 in
                e.x &- PNG.paeth(e.y.a, e.y.z.b, e.y.z.c)
            }
        )
        
        let scores:[Int] = 
        [
            candidates.0, candidates.1, candidates.2, candidates.3, candidates.4
        ].map 
        {
            Self.score($0.dropFirst())
        }
        
        // i don’t know why this isn’t in the standard library
        var filter:Int  = 0,
            minimum:Int = .max
        for (i, score) in scores.enumerated()
        {
            if score < minimum
            {
                minimum = score
                filter  = i
            }
        }
        
        switch filter
        {
            case 0: return candidates.0
            case 1: return candidates.1
            case 2: return candidates.2
            case 3: return candidates.3
            case 4: return candidates.4
            default: fatalError("unreachable: 0 <= filter < 5")
        }
    } 
    
    /* private static
    func score<C>(_ filtered:C) -> Int
        where C:Sequence, C.Element == UInt8
    {
        return zip(filtered, filtered.dropFirst()).reduce(0)
        {
            $0 &+ ($1.0 != $1.1 ? 1 : 0)
        }
    } */
    
    // returns sum of squares of byte frequencies. this biases the score 
    // towards scanlines with many repeated bytes
    /* private static
    func score<C>(_ filtered:C) -> Int
        where C:Sequence, C.Element == UInt8
    {
        var frequencies:[Int] = .init(repeating: 0, count: 256)
        for byte:UInt8 in filtered 
        {
            frequencies[.init(byte)] += 1
        }
        return -frequencies.reduce(0){ $0 + $1 * $1 }
    }  */
    private static
    func score<C>(_ filtered:C) -> Int
        where C:Sequence, C.Element == UInt8
    {
        return filtered.reduce(0){ $0 + abs(.init(Int8.init(bitPattern: $1))) }
    }
}

extension PNG.Data.Rectangular 
{
    public 
    func compress<Destination>(stream:inout Destination, level:Int = 9) throws
        where Destination:PNG.Bytestream.Destination
    {
        try stream.signature()
        
        let header:PNG.Header, 
            palette:PNG.Palette?, 
            background:PNG.Background?, 
            transparency:PNG.Transparency?
        (header, palette, background, transparency) = self.encode()
        
        try stream.format(type: .IHDR, data: header.serialized())
        
        if let chromaticity:PNG.Chromaticity        = self.metadata.chromaticity 
        {
            try stream.format(type: .cHRM, data: chromaticity.serialized())
        }
        if let gamma:PNG.Gamma                      = self.metadata.gamma 
        {
            try stream.format(type: .gAMA, data: gamma.serialized())
        }
        if let colorRendering:PNG.ColorRendering    = self.metadata.colorRendering 
        {
            try stream.format(type: .sRGB, data: colorRendering.serialized())
        }
        if let colorProfile:PNG.ColorProfile        = self.metadata.colorProfile 
        {
            try stream.format(type: .iCCP, data: colorProfile.serialized())
        }
        if let significantBits:PNG.SignificantBits  = self.metadata.significantBits 
        {
            try stream.format(type: .sBIT, data: significantBits.serialized())
        }
        
        
        if let palette:PNG.Palette                  = palette 
        {
            try stream.format(type: .PLTE, data: palette.serialized())
        }
        if let background:PNG.Background            = background
        {
            try stream.format(type: .bKGD, data: background.serialized())
        }
        if let transparency:PNG.Transparency        = transparency
        {
            try stream.format(type: .tRNS, data: transparency.serialized())
        }
        if let histogram:PNG.Histogram              = self.metadata.histogram 
        {
            try stream.format(type: .hIST, data: histogram.serialized())
        }
        
        
        if let dimensions:PNG.PhysicalDimensions    = self.metadata.physicalDimensions 
        {
            try stream.format(type: .pHYs, data: dimensions.serialized())
        }
        if let time:PNG.TimeModified                = self.metadata.time 
        {
            try stream.format(type: .tIME, data: time.serialized())
        }
        
        for text:PNG.Text in self.metadata.text 
        {
            try stream.format(type: .iTXt, data: text.serialized())
        }
        for palette:PNG.SuggestedPalette in self.metadata.suggestedPalettes 
        {
            try stream.format(type: .sPLT, data: palette.serialized())
        }
        for (type, data):(PNG.Chunk, [UInt8]) in self.metadata.application 
        {
            try stream.format(type: type, data: data)
        }
        
        var encoder:PNG.Encoder = .init(interlaced: self.layout.interlaced, level: level)
        while let data:[UInt8] = encoder.pull(size: self.size, 
            pixel:      self.layout.format.pixel, 
            delegate:   self.collect(scanline:at:stride:))  
        {
            try stream.format(type: .IDAT, data: data)
        }
        
        try stream.format(type: .IEND)
    }
}
