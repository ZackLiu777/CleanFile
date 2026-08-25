# ImageFormatConversionKit

An Xcode-ready, Apple-native image conversion component for **CleanMyIPhone**.
The first release deliberately covers still images well instead of hiding an
unmaintained FFmpeg wrapper behind a thin UI.

## What is included

- JPEG, PNG, HEIC, and TIFF output, filtered at runtime by the encoders that
  ImageIO reports on the current device.
- Batch conversion with bounded concurrency (two files by default), task
  cancellation, per-file isolation, and progress reporting.
- Security-scoped access for URLs returned by SwiftUI's file importer.
- EXIF orientation normalized into pixels so removing metadata does not rotate
  the result.
- Original-size or aspect-fit resizing at 4096, 2048, or 1280 pixels.
- Preserve metadata, remove GPS only, or remove all metadata.
- JPEG quality control and white/black flattening for transparent pixels.
- Collision policies (`makeUnique`, `overwrite`, and `fail`) with actor-based
  output-name reservation.
- Temporary-file encoding followed by a same-directory move/replace, so a
  failed conversion does not leave a partial final file.
- SwiftUI + MVVM feature screen with Liquid Glass on iOS 26+ and a material
  fallback.
- English, Simplified Chinese, Traditional Chinese, Korean, French, Japanese,
  and Spanish resources.
- Swift Testing coverage for conversion, resizing, orientation, concurrent
  naming, animated-image rejection, and batch failure isolation.

Animated images are rejected explicitly in this first release; silently taking
the first GIF frame would be data loss disguised as success.

## Add it to CleanMyIPhone

1. Copy the `ImageFormatConversionKit` folder beside the Xcode project.
2. In Xcode, choose **File → Add Package Dependencies → Add Local** and select
   this folder.
3. Add the `ImageFormatConversionKit` product to the CleanMyIPhone app target.
4. Present the feature from an existing `NavigationStack`:

```swift
import ImageFormatConversionKit

NavigationLink("Format Conversion") {
    ImageConversionView()
}
```

The package deployment floor is iOS 17 and therefore works when the app target
is iOS 26 or 27. It does not alter the project's existing deployment target: an
iOS 27 app still needs an iOS 27 simulator, or the app target must be lowered to
match an iOS 26 simulator.

## Use the engine without the supplied UI

```swift
let engine = ImageConversionEngine()

let request = ImageConversionRequest(
    sourceURL: importedURL,
    destinationDirectory: outputDirectory,
    outputFormat: .jpeg,
    quality: 0.82,
    metadataPolicy: .removeGPS,
    resizePolicy: .fit(maxPixelDimension: 2048),
    collisionPolicy: .makeUnique
)

let result = try await engine.convert(request)
print(result.outputURL)
```

`ImageBatchConverter` accepts an array of requests and exposes an async progress
handler. `ImageConversionEngine` is an actor: separate calls may execute their
image work concurrently, while destination-name allocation remains serialized.

## Output and privacy

The provided ViewModel writes into the app's Documents directory under
`Converted Images`. The feature uses the system file importer and only accesses
files the user selects. No network API, analytics call, or server upload is
present.

## Verification policy

The deterministic engine tests live in
`Tests/ImageFormatConversionKitTests/ImageConversionEngineTests.swift` and are
intended for the project's CI test stage. For the existing CleanMyIPhone local
workflow, add the package and perform a normal build; keep `xcodebuild test` in
CI as previously decided.

The current execution environment does not contain Apple's Swift/Xcode
toolchain, so the package is prepared for Xcode compilation but has not been
locally compiled here. The source contains no forced casts, forced tries, or
fatal errors.
