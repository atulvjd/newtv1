import SwiftUI
import Newtv1Core

struct NotchGridMeasurement: Equatable {
    let width: CGFloat
    let height: CGFloat
    let sections: [NotchSection]
    let rowHeight: Double
}

struct NotchGridMeasurementKey: PreferenceKey {
    static let defaultValue: NotchGridMeasurement? = nil
    static func reduce(value: inout NotchGridMeasurement?, nextValue: () -> NotchGridMeasurement?) {
        value = nextValue() ?? value
    }
}

struct NotchModulesGrid: View {
    let width: CGFloat
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController

    var body: some View {
        let configuration = model.notch.normalized()
        let sections = configuration.visibleSections
        let rowHeight = max(80, configuration.horizontalHeight - 28)
        let layout = NotchGridGeometry.calculate(width: width, sectionCount: sections.count, rowHeight: rowHeight)
        VStack(alignment: .leading, spacing: NotchGridGeometry.spacing) {
            ForEach(0..<layout.rows, id: \.self) { row in
                HStack(alignment: .top, spacing: NotchGridGeometry.spacing) {
                    ForEach(Array(sections.dropFirst(row * layout.columns).prefix(layout.columns))) { section in
                        NotchModule(section: section, model: model, speech: speech)
                            .padding(12)
                            .frame(width: layout.cardWidth, alignment: .topLeading)
                            .frame(minHeight: rowHeight, alignment: .topLeading)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(width: max(1, width), alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { actual in
                Color.clear.preference(key: NotchGridMeasurementKey.self, value: NotchGridMeasurement(
                    width: width, height: actual.size.height, sections: sections, rowHeight: configuration.horizontalHeight))
            }
        }
    }
}
