#!/usr/bin/env python3
"""One-off helper that extends frameworks.json (name -> owning framework). Kept for provenance."""
import json
import os

here = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(here, "frameworks.json")
fw = json.load(open(p))


def add(f, names):
    for n in names.split():
        fw["names"][n] = f


add("WidgetKit", "Widget WidgetConfiguration StaticConfiguration AppIntentConfiguration TimelineProvider AppIntentTimelineProvider TimelineEntry Timeline WidgetFamily WidgetPreviewContext AccessoryWidgetBackground WidgetBundle WidgetBundleBuilder WidgetRenderingMode WidgetAccentedRenderingMode ActivityConfiguration WidgetURL WidgetCenter")
add("AppIntents", "AppShortcut AppShortcutsProvider AppShortcutsBuilder IntentDialog DisplayRepresentation TypeDisplayRepresentation IntentResult ProvidesDialog ShowsSnippetView IntentDescription ParameterSummary Parameter AppIntent AppEntity AppEnum IntentFile ReturnsValue OpensIntent EntityQuery WidgetConfigurationIntent SnippetIntent AppIntentsPackage EntityStringQuery IntentParameter")
add("SwiftData", "Query Model Attribute Relationship ModelContainer ModelContext ModelConfiguration FetchDescriptor Schema SchemaMigrationPlan VersionedSchema ModelActor PersistentModel Transient Unique")
add("Charts", "Chart LineMark AreaMark BarMark PointMark RuleMark RectangleMark SectorMark AxisMarks AxisValueLabel AxisGridLine AxisTick ChartContent ChartContentBuilder ChartProxy PlottableValue AxisContent AxisMarkBuilder")
add("MapKit", "Map MapPin MapMarker MapAnnotation MapPolyline MapPolygon MapCircle Marker MapCameraPosition MapStyle MapUserLocationButton MapCompass MapScaleView MapReader MapProxy MapItem")
add("CoreTransferable", "Transferable TransferRepresentation FileRepresentation DataRepresentation ProxyRepresentation CodableRepresentation SentTransferredFile ReceivedTransferredFile")
add("PhotosUI", "PhotosPicker PhotosPickerItem PHPickerViewController")
add("CryptoKit", "SHA256 SHA512 SHA384 SymmetricKey HMAC AES")
add("os", "OSAllocatedUnfairLock OSSpinLock os_unfair_lock Logger OSLog OSLogStore Signposter")
add("Security", "SecItemDelete SecItemAdd SecItemCopyMatching SecItemUpdate SecRandomCopyBytes SecCopyErrorMessageString SecCodeCopyGuestWithAttributes SecCodeCopyStaticCode SecCodeCopySigningInformation SecRequirementCreateWithString SecCodeCheckValidity SecRequirement SecCode SecStaticCode SecCSFlags")
add("Network", "NWConnection NWBrowser NWListener NWEndpoint NWPathMonitor NWParameters")
add("AuthenticationServices", "ASAuthorizationController ASAuthorizationPlatformPublicKeyCredentialProvider ASAuthorizationPasswordProvider ASAuthorizationRequest ASAuthorizationControllerPresentationContextProviding")
add("TVServices", "TVTopShelfAction TVTopShelfItemCollection TVTopShelfSectionedItem TVTopShelfSectionedContent TVTopShelfContentProvider TVTopShelfCarouselContent TVTopShelfInsetContent")
add("Foundation", "LocalizedStringResource ListFormatter RelativeDateTimeFormatter natural_t")
add("Intents", "INShortcut INIntent")
add("system C APIs", "mach_port_t task_power_info_v2 task_vm_info_data_t thread_act_array_t mach_msg_type_number_t thread_t thread_identifier_info thread_extended_info ifaddrs IOPMAssertionID IOPMAssertionCreateWithName IOPMAssertionLevel IOPMAssertionRelease LSOpenFromURLSpec CVPixelBuffer CVPixelBufferLockBaseAddress CVPixelBufferUnlockBaseAddress MTLCreateSystemDefaultDevice SystemSoundID AudioServicesCreateSystemSoundID AudioServicesPlaySystemSound GLenum GLint GLuint")
add("CloudKit", "CKSyncEngine")
add("ActivityKit", "Activity ActivityAttributes ActivityContent")
add("StoreKit", "Product Transaction")
fw["mod_names"].update({"configurationDisplayName": "WidgetKit", "supportedFamilies": "WidgetKit"})
# names that live in shim modules we ship (Combine, Observation): still compile-tested
fw["shim_names"] = {"Published": "Combine", "Observable": "Observation", "ObservationIgnored": "Observation", "Bindable": "Observation"}
json.dump(fw, open(p, "w"), indent=1)
