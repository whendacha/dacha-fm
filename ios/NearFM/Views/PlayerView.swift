import AVKit
import NearFMCore
import SwiftUI

struct MiniPlayer: View {
    let model: AppModel
    var body: some View {
        if let track = model.player.current {
            HStack(spacing: 12) {
                Button { model.playerPresented = true } label: { Artwork(url: track.artworkURL, symbol: "music.note", size: 45) }
                    .buttonStyle(.plain).accessibilityIdentifier("open-player")
                Button { model.playerPresented = true } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(Theme.cream)
                        Text(track.artistName).font(.caption).lineLimit(1).foregroundStyle(Theme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Button { model.player.toggle() } label: {
                    Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).frame(width: 36, height: 40)
                }.accessibilityLabel(model.player.isPlaying ? "Пауза" : "Воспроизвести")
                Button { model.player.next() } label: {
                    Image(systemName: "forward.end.fill").frame(width: 30, height: 40)
                }.accessibilityLabel("Следующая песня")
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    Capsule().fill(Theme.accent)
                        .frame(width: geometry.size.width * CGFloat(model.player.duration > 0 ? min(1, model.player.elapsed / model.player.duration) : 0), height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }.clipShape(RoundedRectangle(cornerRadius: 18)).allowsHitTesting(false)
            }
            .padding(.horizontal, 10).padding(.bottom, 2)
        }
    }
}

struct PlayerView: View {
    let model: AppModel
    @State private var seekValue: Double = 0
    @State private var seeking = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.29, green: 0.18, blue: 0.20), Theme.background, Theme.background], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.weight(.bold)).frame(width: 44, height: 44) }
                        .accessibilityLabel("Свернуть плеер")
                    Spacer()
                    VStack(spacing: 3) {
                        Text("СЕЙЧАС ИГРАЕТ").font(.caption2.weight(.bold)).tracking(2)
                        Text(model.player.artistID == nil ? "Плейлист" : "Только этот автор")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("Выбрать аудиоустройство")
                }
                Spacer(minLength: 20)
                if let track = model.player.current {
                    GeometryReader { geometry in
                        Artwork(url: track.artworkURL, symbol: "waveform", size: min(geometry.size.width, geometry.size.height))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .shadow(color: .black.opacity(0.35), radius: 26, y: 16)
                    }.frame(maxHeight: 370)
                    Spacer(minLength: 28)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title).font(.title2.bold()).lineLimit(2).foregroundStyle(Theme.cream)
                            Text(track.artistName).font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button { model.toggleFavorite(track) } label: {
                            Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                                .font(.title2).foregroundStyle(Theme.accent)
                        }.accessibilityLabel(model.isFavorite(track) ? "Убрать из избранного" : "Добавить в избранное")
                    }
                    VStack(spacing: 4) {
                        Slider(value: $seekValue, in: 0...max(1, model.player.duration)) { editing in
                            seeking = editing
                            if !editing { model.player.seek(to: seekValue) }
                        }
                        .tint(Theme.accent)
                        .onChange(of: model.player.elapsed) { _, value in if !seeking { seekValue = value } }
                        HStack {
                            Text(time(model.player.elapsed)).accessibilityIdentifier("playback-elapsed")
                            Spacer()
                            Text(time(model.player.duration))
                        }.font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                    }.padding(.top, 26)
                    HStack {
                        Button { model.player.shuffle() } label: { Image(systemName: "shuffle").font(.title3) }
                            .accessibilityLabel("Перемешать очередь")
                        Spacer()
                        Button { model.player.previous() } label: { Image(systemName: "backward.end.fill").font(.title2) }
                            .accessibilityLabel("Предыдущая песня")
                        Spacer()
                        Button { model.player.toggle() } label: {
                            Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2).foregroundStyle(.black)
                                .frame(width: 70, height: 70).background(Theme.accent, in: Circle())
                        }.accessibilityLabel(model.player.isPlaying ? "Пауза" : "Воспроизвести")
                        Spacer()
                        Button { model.player.next() } label: { Image(systemName: "forward.end.fill").font(.title2) }
                            .accessibilityLabel("Следующая песня")
                        Spacer()
                        Button { model.player.repeatAll.toggle() } label: {
                            Image(systemName: "repeat").font(.title3).foregroundStyle(model.player.repeatAll ? Theme.accent : Theme.muted)
                        }.accessibilityLabel(model.player.repeatAll ? "Выключить повтор" : "Повторять очередь")
                    }.padding(.top, 27)
                    if let error = model.player.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center).padding(.top, 16)
                    }
                } else {
                    EmptyCard(icon: "music.note", title: "Очередь пуста", detail: "Выберите песню или автора.")
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 22)
        }
        .presentationDragIndicator(.visible)
    }

    private func time(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let seconds = Int(value)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(Theme.cream)
        view.activeTintColor = UIColor(Theme.accent)
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
