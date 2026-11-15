import SwiftUI
import Newtv1Core

struct IslandStudioPreview: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(colors: [model.notch.tint.opacity(0.10), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    HStack { Image(systemName: "sparkle").foregroundStyle(model.notch.tint); Spacer(); Capsule().fill(.black).frame(width: 120, height: 24); Spacer(); Image(systemName: "waveform").foregroundStyle(model.notch.tint) }.padding(.horizontal, 26).frame(height: 38)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Label("Newt", systemImage: "waveform").font(.system(size: 12, weight: .semibold)); Spacer(); Image(systemName: "ellipsis"); Image(systemName: "xmark.circle.fill").foregroundStyle(.gray) }
                        Text("What can I do for you?").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.7)
                        Text("One activity. A little more focus.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                        HStack(spacing: 10) { Label("Start listening", systemImage: "mic.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 38).background(.white, in: Capsule()); Image(systemName: "stop.fill").font(.system(size: 11)).frame(width: 38, height: 38).background(.white.opacity(0.09), in: Circle()); Image(systemName: "arrow.up.right").frame(width: 38, height: 38).background(.white.opacity(0.09), in: Circle()) }.padding(.top, 4)
                    }.padding(24)
                }.frame(width: min(440, max(200, proxy.size.width - 48))).background(.black, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.7))
                    .padding(.top, 20)
                VStack { Spacer(); Text("DYNAMIC ISLAND · COMPACT → FOCUSED → EXPANDED").font(.system(size: 8, design: .monospaced)).tracking(1.3).foregroundStyle(.gray).padding(15) }
            }.frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 18))
        }.allowsHitTesting(false)
    }
}
