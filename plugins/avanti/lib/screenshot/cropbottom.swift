// cropbottom <in.png> <out.png> <width> <height> [inset]: keep width x height pixels at the bottom-left, inset px in.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = Int(a[3])!, h = Int(a[4])!
let inset = a.count > 5 ? Int(a[5])! : 0
let cropped = img.cropping(to: CGRect(x: inset, y: img.height - h - inset, width: w, height: h))!
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, cropped, nil)
CGImageDestinationFinalize(dst)
