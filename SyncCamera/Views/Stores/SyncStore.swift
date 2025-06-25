import Foundation
import MultipeerConnectivity
import OSLog
import Observation
import SwiftUI
import UIKit

protocol SyncDelegate: AnyObject {
  func receivedEvent(_ event: SyncStore.Event)
}

@Observable
final class SyncStore: NSObject, MCSessionDelegate, MCBrowserViewControllerDelegate,
  MCAdvertiserAssistantDelegate, MCNearbyServiceAdvertiserDelegate
{
  weak var delegate: SyncDelegate?

  enum Event: String {
    case takePhoto
  }

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "SyncStore"
  )

  private let serviceType = "sync-camera"
  private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
  private(set) var mcSession: MCSession
  private var mcAdvertiserAssistant: MCAdvertiserAssistant
  private var mcNearbyServiceAdvertiser: MCNearbyServiceAdvertiser

  var mcBrowser: MCBrowserViewController
  private(set) var error: (any Error)?
  var receivedEvent: Event?

  override init() {
    let mcSession = MCSession(
      peer: myPeerID,
      securityIdentity: nil,
      encryptionPreference: .required
    )

    mcAdvertiserAssistant = MCAdvertiserAssistant(
      serviceType: serviceType,
      discoveryInfo: nil,
      session: mcSession
    )

    mcBrowser = MCBrowserViewController(
      serviceType: serviceType,
      session: mcSession
    )

    self.mcSession = mcSession

    self.mcNearbyServiceAdvertiser = .init(
      peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)

    super.init()

    mcSession.delegate = self
    mcAdvertiserAssistant.delegate = self
    self.mcNearbyServiceAdvertiser.delegate = self
  }

  private(set) var isAdvertising: Bool = false

  func startAdvertising() {
    logger.info("\(#function)")
    guard !isAdvertising else { return }
    isAdvertising = true
    mcAdvertiserAssistant.start()
    mcNearbyServiceAdvertiser.startAdvertisingPeer()
  }

  func stopAdvertising() {
    logger.info("\(#function)")
    guard isAdvertising else { return }
    isAdvertising = false
    mcAdvertiserAssistant.stop()
    mcNearbyServiceAdvertiser.stopAdvertisingPeer()
  }

  func startBrowsing() -> MCBrowserViewController {
    logger.info("\(#function)")
    mcBrowser.delegate = self
    return mcBrowser
  }

  func sendEvent(_ event: Event) {
    logger.info("\(#function) event \(event.rawValue)")
    guard let data = event.rawValue.data(using: .utf8) else { return }
    do {
      try mcSession.send(
        data,
        toPeers: mcSession.connectedPeers,
        with: .reliable
      )
    } catch {
      self.error = error
    }
  }

  // MARK: - MCSessionDelegate

  func session(
    _ session: MCSession,
    peer peerID: MCPeerID,
    didChange state: MCSessionState
  ) {
    let stateString: String
    switch state {
    case .notConnected: stateString = "notConnected"
    case .connecting: stateString = "connecting"
    case .connected: stateString = "connected"
    @unknown default: stateString = "unknown"
    }
    logger.info("Peer '\(peerID.displayName)' didChangeState: \(stateString)")
  }

  func session(
    _ session: MCSession,
    didReceive data: Data,
    fromPeer peerID: MCPeerID
  ) {
    let message = String(data: data, encoding: .utf8) ?? "Invalid UTF-8"
    logger.info("Received data from '\(peerID.displayName)': \(message)")
    guard let event = Event(rawValue: message) else { return }
    delegate?.receivedEvent(event)
  }

  func session(
    _ session: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {
    logger.info("Received stream '\(streamName)' from '\(peerID.displayName)'")
  }

  func session(
    _ session: MCSession,
    didReceiveCertificate certificate: [Any]?,
    fromPeer peerID: MCPeerID,
    certificateHandler: @escaping (Bool) -> Void
  ) {
    logger.info(
      "Received certificate from '\(peerID.displayName)', certificate: \(certificate != nil ? "present" : "nil")"
    )
    certificateHandler(true)
  }

  func session(
    _ session: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {
    logger.info("Started receiving resource '\(resourceName)' from '\(peerID.displayName)'")
  }

  func session(
    _ session: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: (any Error)?
  ) {
    if let error {
      logger.error(
        "Failed receiving resource '\(resourceName)' from '\(peerID.displayName)': \(error.localizedDescription)"
      )
    } else {
      logger.info(
        "Finished receiving resource '\(resourceName)' from '\(peerID.displayName)' at \(localURL?.absoluteString ?? "nil")"
      )
    }
  }

  // MARK: - MCBrowserViewControllerDelegate

  func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
    logger.info("\(#function)")
  }

  func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
    logger.info("\(#function)")
  }

  // MARK: - MCAdvertiserAssistantDelegate

  func advertiserAssistantWillPresentInvitation(_ advertiserAssistant: MCAdvertiserAssistant) {
    logger.info("\(#function)")
  }

  func advertiserAssistantDidDismissInvitation(_ advertiserAssistant: MCAdvertiserAssistant) {
    logger.info("\(#function)")
  }

  // MARK: -

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    logger.info("\(#function) context \(String(describing: context))")
    invitationHandler(true, mcSession)
  }
}

struct MultipeerBrowserView: UIViewControllerRepresentable {
  typealias UIViewControllerType = MCBrowserViewController
  let store: SyncStore

  func makeUIViewController(context: Context) -> MCBrowserViewController {
    store.startBrowsing()
  }

  func updateUIViewController(_ uiViewController: MCBrowserViewController, context: Context) {
    // nop
  }
}
