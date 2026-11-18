// faces.swift — 逐格用 Apple Vision 找臉 + 眼睛位置,輸出 JSON lines(每格一行)。給 eyes_mask.py 用。
// 用法: faces <影片> > faces.jsonl   (eyes_mask.py detect 會自動編譯到 ~/.cache/ai-edit/faces)
import AVFoundation
import Vision
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
var track: AVAssetTrack!
Task { track = try! await asset.loadTracks(withMediaType: .video).first!; sem.signal() }
sem.wait()

let reader = try! AVAssetReader(asset: asset)
let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(out)
reader.startReading()

func pts(_ r: VNFaceLandmarkRegion2D?, _ size: CGSize) -> [[Double]] {
    guard let r = r else { return [] }
    return r.pointsInImage(imageSize: size).map { [Double($0.x), Double(size.height - $0.y)] }   // 轉成左上角原點
}

while let sb = out.copyNextSampleBuffer() {
    guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
    let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
    let W = CVPixelBufferGetWidth(pb), H = CVPixelBufferGetHeight(pb)
    let size = CGSize(width: W, height: H)
    let req = VNDetectFaceLandmarksRequest()
    try? VNImageRequestHandler(cvPixelBuffer: pb, options: [:]).perform([req])
    var faces: [[String: Any]] = []
    for f in req.results ?? [] {
        let b = f.boundingBox
        let box = [Double(b.minX) * Double(W), Double(1 - b.maxY) * Double(H), Double(b.width) * Double(W), Double(b.height) * Double(H)]
        let lm = f.landmarks
        faces.append(["box": box, "conf": Double(f.confidence),
                      "yaw": f.yaw?.doubleValue ?? 0,
                      "le": pts(lm?.leftEye, size), "re": pts(lm?.rightEye, size),
                      "lb": pts(lm?.leftEyebrow, size), "rb": pts(lm?.rightEyebrow, size)])
    }
    let line: [String: Any] = ["t": t, "faces": faces]
    let d = try! JSONSerialization.data(withJSONObject: line)
    print(String(data: d, encoding: .utf8)!)
}
