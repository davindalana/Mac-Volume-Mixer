import Foundation
import AppKit
import Combine

/// Observer lifecycle proses aplikasi di macOS menggunakan NSWorkspace notifications.
/// Membantu mendeteksi peluncuran, penutupan, dan identitas metadata aplikasi (nama, bundleID, icon).
public final class ProcessWatcher: @unchecked Sendable {
    // MARK: - Properties
    private let notificationCenter = NSWorkspace.shared.notificationCenter
    private var cancellables = Set<AnyCancellable>()
    
    /// Subject untuk memancarkan event saat terjadi perubahan aplikasi yang berjalan
    private let appsChangedSubject = PassthroughSubject<Void, Never>()
    
    /// Publisher publik untuk mendengarkan perubahan daftar aplikasi
    public var onAppsChanged: AnyPublisher<Void, Never> {
        appsChangedSubject.eraseToAnyPublisher()
    }
    
    /// Cache memori icon untuk efisiensi render UI dan menghindari disk I/O berulang
    private var iconCache = [pid_t: NSImage]()
    private let lock = NSLock()
    
    // MARK: - Initializer
    public init() {
        startObserving()
    }
    
    deinit {
        stopObserving()
    }
    
    // MARK: - Observation Setup
    
    /// Memulai observasi notifikasi NSWorkspace untuk lifecycle aplikasi
    public func startObserving() {
        // Notifikasi saat aplikasi baru dijalankan
        notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notification in
                self?.handleAppChange(notification: notification)
            }
            .store(in: &cancellables)
        
        // Notifikasi saat aplikasi ditutup/terminate
        notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.removeCachedIcon(for: app.processIdentifier)
                }
                self?.handleAppChange(notification: notification)
            }
            .store(in: &cancellables)
        
        // Notifikasi saat aplikasi berganti aktif
        notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                self?.handleAppChange(notification: notification)
            }
            .store(in: &cancellables)
    }
    
    /// Menghentikan seluruh observasi
    public func stopObserving() {
        cancellables.removeAll()
        lock.lock()
        iconCache.removeAll()
        lock.unlock()
    }
    
    private func handleAppChange(notification: Notification) {
        appsChangedSubject.send(())
    }
    
    // MARK: - Helper Methods
    
    /// Mengambil objek `NSRunningApplication` berdasarkan Process ID
    public func runningApp(for pid: pid_t) -> NSRunningApplication? {
        return NSRunningApplication(processIdentifier: pid)
    }
    
    /// Mengambil metadata aplikasi lengkap (Nama, Bundle Identifier, dan Icon)
    public func appInfo(for pid: pid_t) -> (name: String, bundleID: String?, icon: NSImage?) {
        if let runningApp = NSRunningApplication(processIdentifier: pid) {
            let name = runningApp.localizedName ?? "Process \(pid)"
            let bundleID = runningApp.bundleIdentifier
            let icon = cachedIcon(for: pid) ?? runningApp.icon
            
            if let icon = icon {
                cacheIcon(icon, for: pid)
            }
            return (name, bundleID, icon)
        }
        
        // Fallback jika proses adalah daemon/cli tanpa NSRunningApplication
        return ("Process \(pid)", nil, nil)
    }
    
    /// Mengambil seluruh aplikasi aktif yang memiliki UI reguler
    public func getRegularRunningApplications() -> [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
    }
    
    // MARK: - Icon Cache
    
    private func cachedIcon(for pid: pid_t) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return iconCache[pid]
    }
    
    private func cacheIcon(_ icon: NSImage, for pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        iconCache[pid] = icon
    }
    
    private func removeCachedIcon(for pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        iconCache.removeValue(forKey: pid)
    }
}
