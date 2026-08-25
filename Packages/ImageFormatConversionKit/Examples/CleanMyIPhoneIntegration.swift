import ImageFormatConversionKit
import SwiftUI

/// Add the package as a local dependency, then route to this view from CleanMyIPhone.
struct FormatConversionRoute: View {
    var body: some View {
        NavigationStack {
            ImageConversionView()
        }
    }
}
