import SwiftUI
import CoreImage.CIFilterBuiltins
import CoreLocation
import SystemConfiguration.CaptiveNetwork
import Photos
import UIKit

// Extension to resign first responder (dismiss keyboard)
extension UIApplication {
    func endEditing() {
        sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

@main
struct QRCodeGeneratorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
            // default accentColor = blue for buttons & pickers
        }
    }
}

struct ContentView: View {
    // MARK: Models
    enum DataType: String, CaseIterable, Identifiable {
        case url   = "URL"
        case text  = "Text"
        case phone = "Phone"
        case sms   = "SMS"
        case email = "Email"
        case wifi  = "Wi-Fi"
        case vcard = "Contact"
        case geo   = "Location"
        case event = "Event"
        var id: String { rawValue }
    }
    enum WiFiEncryption: String, CaseIterable, Identifiable {
        case open = "nopass", wep = "WEP", wpa = "WPA"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .open: return "Open"
            case .wep:  return "WEP"
            case .wpa:  return "WPA/WPA2/WPA3"
            }
        }
    }
    enum GeoInputType: String, CaseIterable, Identifiable {
        case address     = "Address"
        case coordinates = "Coordinates"
        var id: String { rawValue }
    }

    // MARK: State
    @State private var selectedType   = DataType.url

    // URL / Text
    @State private var inputData      = ""

    // Email
    @State private var emailAddress   = ""
    @State private var emailBody      = ""

    // SMS
    @State private var smsNumber      = ""
    @State private var smsMessage     = ""

    // Wi-Fi
    @State private var wifiSSID       = ""
    @State private var wifiEncryption = WiFiEncryption.wpa
    @State private var wifiPassword   = ""

    // vCard
    @State private var vcardName      = ""
    @State private var vcardPhone     = ""
    @State private var vcardEmail     = ""

    // Geo
    @State private var geoInputType   = GeoInputType.address
    @State private var latitude       = ""
    @State private var longitude      = ""
    @State private var addressQuery   = ""

    // Event
    @State private var eventSummary   = ""
    @State private var eventLocation  = ""
    @State private var eventStart     = Date()
    @State private var eventEnd       = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()

    // QR & UI
    @State private var qrImage: UIImage?
    @State private var showShareSheet = false

    // Zoom/slide state
    @State private var isZoomed       = false

    // Helpers
    private let context  = CIContext()
    private let filter   = CIFilter.qrCodeGenerator()
    private let geocoder = CLGeocoder()

    var body: some View {
        ZStack {
            // 1) Main UI, blurred when zoomed
            NavigationStack {
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                        .onTapGesture { UIApplication.shared.endEditing() }

                    GeometryReader { geo in
                        VStack(spacing: 16) {
                            typePicker
                            dynamicForm
                                .padding(.horizontal)
                            qrPreview(in: geo.size)
                                .padding()
                            Spacer()
                        }
                    }
                }
                .navigationTitle("QR Code Generator")
                .toolbar { toolbarButtons }
                .onAppear { generateQRCode() }
            }
            .blur(radius: isZoomed ? 10 : 0)
            .animation(.easeInOut(duration: 0.3), value: isZoomed)

            // 2) Overlay: darkened + slide-up QR
            GeometryReader { geo in
                ZStack {
                    Color.black
                        .opacity(isZoomed ? 0.6 : 0)
                        .ignoresSafeArea()
                        .onTapGesture {
                            if isZoomed {
                                withAnimation { isZoomed = false }
                            }
                        }

                    if isZoomed, let img = qrImage {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: geo.size.width * 0.8)
                            .cornerRadius(12)
                            .shadow(radius: 10)
                            .offset(y: isZoomed ? 0 : geo.size.height)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isZoomed)
                            .onTapGesture { /* consume tap */ }
                    }
                }
                .allowsHitTesting(isZoomed)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - QR Preview
    private func qrPreview(in size: CGSize) -> some View {
        Group {
            if let img = qrImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(
                        maxWidth: size.width * 0.9,
                        maxHeight: size.height * 0.9
                    )
                    .cornerRadius(12)
                    .onTapGesture { withAnimation { isZoomed = true } }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dynamic Form
    private var typePicker: some View {
        Picker("Type", selection: $selectedType) {
            ForEach(DataType.allCases) {
                Text($0.rawValue).tag($0)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .padding(.horizontal)
        .onChange(of: selectedType) {
            clearInputs()
            generateQRCode()
        }
    }

    @ViewBuilder
    private var dynamicForm: some View {
        switch selectedType {
        case .url:   urlField()
        case .text:  textField()
        case .email: emailFields()
        case .phone: phoneFields()
        case .sms:   smsFields()
        case .wifi:  wifiFields()
        case .vcard: vcardFields()
        case .geo:   geoFields()
        case .event: eventFields()
        }
    }

    // MARK: Field Builders

    @ViewBuilder
    private func urlField() -> some View {
        TextField(
            "",
            text: $inputData,
            prompt: Text("https://example.com").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .tint(.secondary)
        .onChange(of: inputData) { generateQRCode() }
    }

    @ViewBuilder
    private func textField() -> some View {
        TextField(
            "",
            text: $inputData,
            prompt: Text("Any text").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .tint(.secondary)
        .onChange(of: inputData) { generateQRCode() }
    }

    @ViewBuilder private func emailFields() -> some View {
        TextField(
            "",
            text: $emailAddress,
            prompt: Text("example@example.com").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .tint(.secondary)
        .keyboardType(.emailAddress)
        .autocapitalization(.none)
        .onChange(of: emailAddress) { generateQRCode() }

        ZStack(alignment: .topLeading) {
            if emailBody.isEmpty {
                Text("Email body")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
            TextEditor(text: $emailBody)
                .frame(minHeight: 100)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.5))
                )
                .onChange(of: emailBody) { generateQRCode() }
        }
    }

    @ViewBuilder private func phoneFields() -> some View {
        TextField(
            "",
            text: $smsNumber,
            prompt: Text("+15551234567").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .keyboardType(.phonePad)
        .onChange(of: smsNumber) { generateQRCode() }
    }

    @ViewBuilder private func smsFields() -> some View {
        TextField(
            "",
            text: $smsNumber,
            prompt: Text("+15551234567").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .keyboardType(.phonePad)
        .onChange(of: smsNumber) { generateQRCode() }

        TextField(
            "",
            text: $smsMessage,
            prompt: Text("Your message").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .onChange(of: smsMessage) { generateQRCode() }
    }

    @ViewBuilder private func wifiFields() -> some View {
        TextField(
            "",
            text: $wifiSSID,
            prompt: Text("Network SSID").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .onChange(of: wifiSSID) { generateQRCode() }

        Picker("Encryption", selection: $wifiEncryption) {
            ForEach(WiFiEncryption.allCases) {
                Text($0.label).tag($0)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .onChange(of: wifiEncryption) { generateQRCode() }

        if wifiEncryption != .open {
            SecureField(
                "",
                text: $wifiPassword,
                prompt: Text("Password").foregroundColor(.secondary)
            )
            .textFieldStyle(.roundedBorder)
            .onChange(of: wifiPassword) { generateQRCode() }
        }
    }

    @ViewBuilder private func vcardFields() -> some View {
        TextField(
            "",
            text: $vcardName,
            prompt: Text("Full Name").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .onChange(of: vcardName) { generateQRCode() }

        TextField(
            "",
            text: $vcardPhone,
            prompt: Text("+15551234567").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .keyboardType(.phonePad)
        .onChange(of: vcardPhone) { generateQRCode() }

        TextField(
            "",
            text: $vcardEmail,
            prompt: Text("example@example.com").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .autocapitalization(.none)
        .onChange(of: vcardEmail) { generateQRCode() }
    }

    @ViewBuilder private func geoFields() -> some View {
        Picker("Location Input", selection: $geoInputType) {
            ForEach(GeoInputType.allCases) {
                Text($0.rawValue).tag($0)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .onChange(of: geoInputType) { generateQRCode() }

        if geoInputType == .address {
            TextField(
                "",
                text: $addressQuery,
                prompt: Text("1600 Amphitheatre Parkway, Mountain View, CA")
                    .foregroundColor(.secondary)
            )
            .textFieldStyle(.roundedBorder)
            .onChange(of: addressQuery) { generateQRCode() }
        } else {
            TextField(
                "",
                text: $latitude,
                prompt: Text("37.7749").foregroundColor(.secondary)
            )
            .textFieldStyle(.roundedBorder)
            .keyboardType(.decimalPad)
            .onChange(of: latitude) { generateQRCode() }

            TextField(
                "",
                text: $longitude,
                prompt: Text("-122.4194").foregroundColor(.secondary)
            )
            .textFieldStyle(.roundedBorder)
            .keyboardType(.decimalPad)
            .onChange(of: longitude) { generateQRCode() }
        }
    }
    
    // MARK: – Toolbar
    private var toolbarButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button(action: savePhoto) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = qrImage {
                    ShareSheet(activityItems: [img])
                }
            }
            NavigationLink(destination: AboutView()) {
                Label("About", systemImage: "info.circle")
            }
        }
    }

    // MARK: - Event Fields (with validation)
    @ViewBuilder
    private func eventFields() -> some View {
        TextField(
            "",
            text: $eventSummary,
            prompt: Text("Event Title").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .onChange(of: eventSummary) { generateQRCode() }

        DatePicker(
            "Start",
            selection: $eventStart,
            displayedComponents: [.date, .hourAndMinute]
        )
        .onChange(of: eventStart) {
            let minEnd = Calendar.current.date(byAdding: .hour, value: 1, to: eventStart)!
            if eventEnd < minEnd {
                eventEnd = minEnd
            }
            generateQRCode()
        }

        DatePicker(
            "End",
            selection: $eventEnd,
            displayedComponents: [.date, .hourAndMinute]
        )
        .onChange(of: eventEnd) {
            let minEnd = Calendar.current.date(byAdding: .hour, value: 1, to: eventStart)!
            if eventEnd < minEnd {
                eventEnd = minEnd
            }
            generateQRCode()
        }

        TextField(
            "",
            text: $eventLocation,
            prompt: Text("Location").foregroundColor(.secondary)
        )
        .textFieldStyle(.roundedBorder)
        .onChange(of: eventLocation) { generateQRCode() }
    }

    // MARK: – Core Logic
    private func clearInputs() {
        inputData      = ""
        emailAddress   = ""
        emailBody      = ""
        smsNumber      = ""
        smsMessage     = ""
        wifiSSID       = ""
        wifiEncryption = .wpa
        wifiPassword   = ""
        vcardName      = ""
        vcardPhone     = ""
        vcardEmail     = ""
        geoInputType   = .address
        latitude       = ""
        longitude      = ""
        addressQuery   = ""
        eventSummary   = ""
        eventLocation  = ""
        eventStart     = Date()
        eventEnd       = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        qrImage        = nil
    }

    private func generateQRCode() {
        let payload: String
        switch selectedType {
        case .url, .text:
            payload = inputData
        case .email:
            let b = emailBody.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? ""
            payload = "mailto:\(emailAddress)?body=\(b)"
        case .phone:
            payload = "tel:\(smsNumber)"
        case .sms:
            payload = "SMSTO:\(smsNumber):\(smsMessage)"
        case .wifi:
            payload = "WIFI:S:\(wifiSSID);T:\(wifiEncryption.rawValue);P:\(wifiPassword);;"
        case .vcard:
            payload = """
            BEGIN:VCARD
            VERSION:3.0
            FN:\(vcardName)
            TEL:\(vcardPhone)
            EMAIL:\(vcardEmail)
            END:VCARD
            """
        case .geo:
            if geoInputType == .coordinates {
                payload = "geo:\(latitude),\(longitude)"
            } else {
                let q = addressQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                payload = "maps:?q=\(q)"
            }
        case .event:
            let df = DateFormatter()
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            let now   = Date()
            let stamp = df.string(from: now)
            let s     = df.string(from: eventStart)
            let e     = df.string(from: eventEnd)
            let uid   = UUID().uuidString + "@qrcodegenerator"
            payload = """
            BEGIN:VCALENDAR\r\n\
            VERSION:2.0\r\n\
            PRODID:-//QR Code Generator//EN\r\n\
            BEGIN:VEVENT\r\n\
            UID:\(uid)\r\n\
            DTSTAMP:\(stamp)\r\n\
            DTSTART:\(s)\r\n\
            DTEND:\(e)\r\n\
            SUMMARY:\(eventSummary)\r\n\
            LOCATION:\(eventLocation)\r\n\
            END:VEVENT\r\n\
            END:VCALENDAR\r\n
            """
        }

        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        if let ci = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 20, y: 20)),
           let cg = context.createCGImage(ci, from: ci.extent)
        {
            qrImage = UIImage(cgImage: cg)
        }
    }

    private func savePhoto() {
        guard let img = qrImage else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: img)
            }
        }
    }

    private func getCurrentSSID() -> String? {
        guard let ifs = CNCopySupportedInterfaces() as? [String] else { return nil }
        for iface in ifs {
            if let info = CNCopyCurrentNetworkInfo(iface as CFString) as?
                    [String: AnyObject],
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String
            {
                return ssid
            }
        }
        return nil
    }
}


// Share sheet helper
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }
    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

// MARK: About View
struct AppInfo {
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
    }
    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "Unknown"
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("MyQRKit")
                .font(.title)
                .bold()
            Text("by Tyler Davis")
                .font(.subheadline)
            Divider()
            Text("Version: \(AppInfo.version)")
            Text("Build: \(AppInfo.build)")
            Spacer()
        }
        .padding()
        .navigationTitle("About")
    }
}



// Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
