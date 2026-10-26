import AppKit
import SwiftUI

struct ContentView: View {
    @State private var vm = PlayerViewModel()
    @State private var showSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var bvm = vm
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            if vm.isCompactMode {
                CompactLyricsView()
                    .transition(.opacity.animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.22)))
            } else if vm.tracks.isEmpty && vm.libraryFolders.isEmpty && !vm.isScanning {
                OnboardingView(onChooseFolder: openFolderPicker) { url in
                    Task { await vm.loadFolder(url) }
                }
                .transition(.opacity.animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.28)))
            } else {
                fullLayout
                    .transition(.opacity.animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.28)))
            }
        }
        .frame(minWidth: 1, minHeight: 1)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .environment(vm)
        .sheet(isPresented: $bvm.isShowingManualSearch) {
            ManualLyricsSearchSheet(isPresented: $bvm.isShowingManualSearch)
                .environment(vm)
        }
        .sheet(isPresented: $bvm.isShowingLyricsEditor) {
            LyricsEditorSheet(isPresented: $bvm.isShowingLyricsEditor)
                .environment(vm)
        }
        .onChange(of: vm.isCompactMode) { _, compact in
            resizeWindowForMode(compact: compact)
        }
        .task {
            // SwiftUI focuses the search field once the window is key; take it
            // back so typing Space plays instead of landing in the field.
            try? await Task.sleep(for: .milliseconds(250))
            if vm.searchText.isEmpty { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .task {
            #if DEBUG
            DemoMode.prepare()
            #endif
            vm.setupRemoteCommands()
            vm.applyWindowPin()
            if vm.isCompactMode { applyCompactConstraints() } else { applyFullConstraints() }
            await vm.restoreLastFolder()
            #if DEBUG
            await DemoMode.run(vm) { showSettings = true }
            #endif
            await vm.runPostLaunchTasks()
        }
        // Global keyboard shortcuts
        .lyraKeyboardShortcuts(vm: vm)
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
                .environment(vm)
        }
    }

    // MARK: - Layouts

    private var fullLayout: some View {
        HStack(spacing: 0) {
            if vm.isSidebarVisible {
                SidebarView(onOpenSettings: { showSettings = true })
                .frame(width: 232)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                mainTopBar

                ZStack(alignment: .bottom) {
                    Group {
                        if vm.mainView == .lyrics, vm.currentTrack != nil {
                            LyricsView()
                        } else if vm.mainView == .visualizer, vm.currentTrack != nil {
                            VisualizerView()
                        } else {
                            BrowseView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Scrolling content fades out under the top bar instead
                    // of running behind the search pill.
                    .mask {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 20)
                            Color.black
                        }
                    }
                    .transition(.opacity)

                    if vm.currentTrack != nil {
                        PlayerBarView()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.2), value: vm.mainView)
                .animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.25), value: vm.currentTrack)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Same spot whether the sidebar is open or not: right of the traffic lights.
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.3, dampingFraction: 0.85)) {
                    vm.isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(CircleIconButtonStyle())
            .help(vm.isSidebarVisible ? "Hide sidebar" : "Show sidebar")
            .frame(height: Theme.topBarHeight)
            .padding(.leading, 84)
        }
        // The top bar shares the title bar row with the traffic lights.
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Main top bar

    /// Search in the middle, lyrics actions and window controls on the right.
    private var mainTopBar: some View {
        @Bindable var bvm = vm
        return ZStack {
            SearchPill(text: $bvm.searchText) {
                if let top = vm.searchResults.top { vm.open(top) }
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                if vm.mainView == .lyrics, vm.currentTrack != nil {
                    topBarButton(systemImage: "square.and.pencil", help: "Edit / Import lyrics") {
                        vm.isShowingLyricsEditor = true
                    }
                    topBarButton(systemImage: "text.magnifyingglass", help: "Manual lyrics search") {
                        vm.isShowingManualSearch = true
                    }
                }

                topBarButton(systemImage: "pip.enter", help: "Compact mode") {
                    withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.35, dampingFraction: 0.75)) {
                        vm.isCompactMode = true
                    }
                }

                topBarButton(
                    systemImage: vm.isPinned ? "pin.fill" : "pin",
                    help: vm.isPinned ? "Unpin window" : "Keep window on top",
                    isActive: vm.isPinned
                ) {
                    vm.isPinned.toggle()
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Theme.topBarHeight)
        .animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.18), value: vm.mainView)
    }

    private func topBarButton(
        systemImage: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(CircleIconButtonStyle(isActive: isActive))
        .help(help)
    }

    // MARK: - Window resize for compact mode

    private static let compactFrameKey = "lyra.compactWindowFrame"
    private static let fullFrameKey    = "lyra.fullWindowFrame"

    private static let defaultCompactSize = CGSize(width: 320, height: 480)
    private static let defaultFullSize    = CGSize(width: 1200, height: 760)

    /// Constraints only, no resize: on launch the window already has the right size.
    private func applyCompactConstraints() {
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            window.minSize = CGSize(width: 160, height: 200)
            window.maxSize = CGSize(width: 500, height: 900)
            Self.configureTitlebar(window, compact: true)
        }
    }

    /// Full-mode minimum size at launch; otherwise the window inherits the root
    /// view's `minWidth: 1` and can be dragged down to a few pixels.
    private func applyFullConstraints() {
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            window.minSize = CGSize(width: 750, height: 520)
            window.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
            Self.configureTitlebar(window, compact: false)
        }
    }

    /// An empty unified toolbar makes the title bar as tall as the top bar, so
    /// the traffic lights line up with the sidebar toggle and the search pill.
    /// Compact mode drops it to keep the small window's chrome minimal.
    private static func configureTitlebar(_ window: NSWindow, compact: Bool) {
        if compact {
            window.toolbar = nil
        } else if window.toolbar == nil {
            window.toolbar = NSToolbar(identifier: "lyra.main")
            window.toolbarStyle = .unified
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
    }

    private func resizeWindowForMode(compact: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            self._doResize(compact: compact)
        }
    }

    private func _doResize(compact: Bool) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        if compact {
            // Save current full-mode frame before switching
            saveFrame(window.frame, key: Self.fullFrameKey)
            Self.configureTitlebar(window, compact: true)

            window.minSize = CGSize(width: 160, height: 200)
            window.maxSize = CGSize(width: 500, height: 900)

            let target = savedFrame(key: Self.compactFrameKey)
                ?? centeredFrame(size: Self.defaultCompactSize, in: window)
            window.setFrame(target, display: true, animate: true)
        } else {
            // Save current compact frame before switching
            saveFrame(window.frame, key: Self.compactFrameKey)
            Self.configureTitlebar(window, compact: false)

            window.minSize = CGSize(width: 1, height: 1)
            window.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)

            let target = savedFrame(key: Self.fullFrameKey)
                ?? centeredFrame(size: Self.defaultFullSize, in: window)
            window.setFrame(target, display: true, animate: false)
            DispatchQueue.main.async {
                window.minSize = CGSize(width: 750, height: 520)
            }
        }
    }

    private func saveFrame(_ frame: NSRect, key: String) {
        let d = ["x": frame.origin.x, "y": frame.origin.y,
                 "w": frame.width,    "h": frame.height]
        UserDefaults.standard.set(d, forKey: key)
    }

    private func savedFrame(key: String) -> NSRect? {
        guard let d = UserDefaults.standard.dictionary(forKey: key),
              let x = d["x"] as? CGFloat, let y = d["y"] as? CGFloat,
              let w = d["w"] as? CGFloat, let h = d["h"] as? CGFloat,
              w > 0, h > 0
        else { return nil }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func centeredFrame(size: CGSize, in window: NSWindow) -> NSRect {
        NSRect(x: window.frame.midX - size.width / 2,
               y: window.frame.midY - size.height / 2,
               width: size.width, height: size.height)
    }

    // MARK: - Folder picker

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose your music folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await vm.loadFolder(url) }
    }
}

/// Global transport shortcuts (space = play/pause, ←/→ = prev/next).
///
/// A local event monitor instead of `.onKeyPress`, which only fires while the
/// root view has focus: buttons and scroll views would swallow Space first.
/// Text fields still get their keystrokes.
private struct LyraKeyboardShortcutsModifier: ViewModifier {
    let vm: PlayerViewModel
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    // NSEvent isn't Sendable: copy the values out first. The
                    // monitor already runs on the main thread.
                    let keyCode = event.keyCode
                    let modifiers = event.modifierFlags
                    let consumed = MainActor.assumeIsolated {
                        handle(keyCode: keyCode, modifiers: modifiers)
                    }
                    return consumed ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    /// Returns `true` if the key was handled and should be swallowed.
    @MainActor
    private func handle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        // Let text fields (e.g. the search box) keep their keystrokes.
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSText || responder is NSTextView {
            return false
        }
        // Only plain keys — leave anything with ⌘/⌥/⌃/⇧ to menus & system.
        guard modifiers.intersection(.deviceIndependentFlagsMask).isEmpty else {
            return false
        }

        switch keyCode {
        case 49:  vm.togglePlayPause(); return true   // space
        case 123: vm.playPrevious();    return true   // ←
        case 124: vm.playNext();        return true   // →
        default:  return false
        }
    }
}

private extension View {
    func lyraKeyboardShortcuts(vm: PlayerViewModel) -> some View {
        modifier(LyraKeyboardShortcutsModifier(vm: vm))
    }
}
