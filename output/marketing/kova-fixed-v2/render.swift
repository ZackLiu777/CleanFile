import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1]);let W:CGFloat=1206,H:CGFloat=2622
let old="/Users/zaneliao/Downloads/output/marketing/unified-iphone-v1/"
let names=["01-cleanup","02-videos","03-photos","04-duplicates","05-swipe","06-screenshots","07-storage","08-convert"]
let headlines=[["Free Up","30GB+ Space"],["Shrink Big","Videos"],["Compress","Photos"],["Delete","Duplicates"],["Swipe to","Clean"],["Clean","Screenshots"],["X-Ray","Storage"],["Convert","Media"]]
let sources=[old+"01-cleanup.png",old+"06-videos.png",old+"03-compression.png",old+"04-similar.png","/Users/zaneliao/Downloads/IMG_3071.PNG","/Users/zaneliao/Downloads/IMG_3073.PNG","/Users/zaneliao/Downloads/IMG_3069.PNG","/Users/zaneliao/Downloads/IMG_3067.PNG"]
func r(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat)->CGRect{CGRect(x:x,y:H-y-h,width:w,height:h)}
func c(_ v:Int)->NSColor{NSColor(srgbRed:CGFloat(v>>16&255)/255,green:CGFloat(v>>8&255)/255,blue:CGFloat(v&255)/255,alpha:1)}
func rr(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ radius:CGFloat,_ color:NSColor){color.setFill();NSBezierPath(roundedRect:r(x,y,w,h),xRadius:radius,yRadius:radius).fill()}
func bm(_ w:Int,_ h:Int)->NSBitmapImageRep{NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!}
func font(_ n:CGFloat)->NSFont{NSFont(name:"ArialRoundedMTBold",size:n) ?? NSFont.systemFont(ofSize:n,weight:.heavy)}
func text(_ t:String,_ y:CGFloat,_ size:CGFloat){(t as NSString).draw(in:r(108,y,1040,170),withAttributes:[.font:font(size),.foregroundColor:c(0x0754CC)])}
func star(_ x:CGFloat,_ y:CGFloat,_ size:CGFloat){let p=NSBezierPath();let pts:[(CGFloat,CGFloat)]=[(0,-1),(0.25,-0.25),(1,0),(0.25,0.25),(0,1),(-0.25,0.25),(-1,0),(-0.25,-0.25)];for(i,a)in pts.enumerated(){let q=NSPoint(x:x+a.0*size,y:H-(y+a.1*size));if i==0{p.move(to:q)}else{p.line(to:q)}};p.close();c(0x238EFF).setFill();p.fill()}
var manifest:[[String:Any]]=[]
for i in 0..<8 {
 let b=bm(1206,2622);NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:b)!;NSGraphicsContext.current!.imageInterpolation = .high
 NSGradient(starting:c(0xC6E0FF),ending:c(0xEBF4FF))!.draw(in:CGRect(x:0,y:0,width:W,height:H),angle:90)
 c(0xB8DCFF).setFill();NSBezierPath(ovalIn:r(-400,-380,850,650)).fill();NSBezierPath(ovalIn:r(1010,570,600,1040)).fill();NSBezierPath(ovalIn:r(-370,1830,600,760)).fill()
 var fs:CGFloat=158;while headlines[i].map{($0 as NSString).size(withAttributes:[.font:font(fs)]).width}.max()!>1010{fs-=1}
 for(j,line)in headlines[i].enumerated(){text(line,150+CGFloat(j)*177,fs)}
 star(1040,150,28);star(1000,255,45);star(1090,330,25)
 let wave=NSBezierPath();wave.move(to:NSPoint(x:112,y:H-535));wave.curve(to:NSPoint(x:244,y:H-535),controlPoint1:NSPoint(x:178,y:H-580),controlPoint2:NSPoint(x:178,y:H-490));wave.curve(to:NSPoint(x:376,y:H-535),controlPoint1:NSPoint(x:310,y:H-580),controlPoint2:NSPoint(x:310,y:H-490));wave.curve(to:NSPoint(x:508,y:H-535),controlPoint1:NSPoint(x:442,y:H-580),controlPoint2:NSPoint(x:442,y:H-490));wave.lineWidth=21;wave.lineCapStyle = .round;c(0x238EFF).setStroke();wave.stroke()
 let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.25);shadow.shadowBlurRadius=35;shadow.shadowOffset=NSSize(width:0,height:-12);NSGraphicsContext.saveGraphicsState();shadow.set();rr(160,650,886,1926,130,.black);NSGraphicsContext.restoreGraphicsState()
 rr(160,650,886,1926,130,c(0x3D4144));rr(165,655,876,1916,125,c(0xA3A8AE));rr(172,662,862,1902,118,.black)
 rr(152,930,8,110,4,c(0x777E84));rr(152,1080,8,150,4,c(0x777E84));rr(1046,1020,8,180,4,c(0x777E84))
 let image=NSImage(contentsOfFile:sources[i])!;let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil)!
 let content:CGImage=i<4 ? cg.cropping(to:CGRect(x:177,y:584,width:852,height:1902))! : cg
 // Fixed screen container, with aspect-fit only. Original UI pixels are never stretched or repainted.
 NSGraphicsContext.saveGraphicsState();NSBezierPath(roundedRect:r(184,674,838,1878),xRadius:106,yRadius:106).addClip();rr(184,674,838,1878,0,c(0xB8E6F9))
 let scale=min(838/CGFloat(content.width),1878/CGFloat(content.height));let w=CGFloat(content.width)*scale,h=CGFloat(content.height)*scale
 NSImage(cgImage:content,size:NSSize(width:content.width,height:content.height)).draw(in:r(184+(838-w)/2,674+(1878-h)/2,w,h))
 NSGraphicsContext.restoreGraphicsState();NSGraphicsContext.restoreGraphicsState()
 try b.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(names[i]+".png"))
 manifest.append(["file":names[i]+".png","source":sources[i],"originalAppScreenshot":i>=4,"canvas":[1206,2622],"phoneBody":[160,650,886,1926],"screen":[184,674,838,1878],"fit":"aspect-fit; UI unchanged"])
}
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("layout-manifest.json"))
let sheet=bm(1440,1566);NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:sheet)!;for(i,n)in names.enumerated(){NSImage(contentsOf:root.appendingPathComponent(n+".png"))!.draw(in:CGRect(x:(i%4)*360,y:1566-(i/4+1)*783,width:360,height:783))};NSGraphicsContext.restoreGraphicsState();try sheet.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("overview.png"))
