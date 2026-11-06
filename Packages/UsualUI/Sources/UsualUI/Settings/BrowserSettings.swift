import HermesKit
import SwiftUI

/// How a Bot's browser is shown on this device: one choice for every Bot, kept on the device.
struct BrowserSettings: View {
    @AppStorage(BrowserPicture.qualityKey) private var quality = BrowserPicture.Quality.standard.rawValue
    @AppStorage(BrowserPicture.densityKey) private var density = 1

    var body: some View {
        Section {
            Picker("Picture quality", selection: $quality) {
                Text("Data Saver").tag(BrowserPicture.Quality.dataSaver.rawValue)
                Text("Standard").tag(BrowserPicture.Quality.standard.rawValue)
                Text("Best").tag(BrowserPicture.Quality.best.rawValue)
            }
            .clickable()
            Picker("Pixel density", selection: $density) {
                Text("1×").tag(1)
                Text("2×").tag(2)
            }
            .clickable()
        } header: {
            Text("Bot’s Browser")
        } footer: {
            Text(
                "For watching a Bot’s browser on this device. Best is lossless and several times bigger than Standard. 2× makes text sharper on high-resolution screens and uses about four times the data. Neither changes the Bot’s browser."
            )
        }
    }
}
