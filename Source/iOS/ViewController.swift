//
//  ViewController.swift
//  DeckRocket
//
//  Created by JP Simard on 6/13/14.
//  Copyright (c) 2014 JP Simard. All rights reserved.
//

import Cartography
import MultipeerConnectivity
import UIKit
import WatchConnectivity

final class ViewController: UICollectionViewController, WCSessionDelegate {

    // MARK: Properties

    var slides: [Slide]? {
        didSet {
            dispatch_async(dispatch_get_main_queue()) {
                self.infoLabel.hidden = self.slides != nil
                self.collectionView?.contentOffset.x = 0
                self.collectionView?.reloadData()
                // Trigger state change block
                self.multipeerClient.onStateChange??(state: self.multipeerClient.state,
                    peerID: MCPeerID(displayName: "placeholder"))
            }
            sendSlidesToWatch(watchConnectivitySession)
        }
    }
    private let multipeerClient = MultipeerClient()
    private let infoLabel = UILabel()
    private let watchConnectivitySession = WCSession.defaultSession()

    // MARK: View Lifecycle

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .Horizontal
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        super.init(collectionViewLayout: layout)
        watchConnectivitySession.delegate = self
    }

    convenience required init(coder aDecoder: NSCoder) {
        self.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        setupConnectivityObserver()
        let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory,
            .UserDomainMask, true)[0] as NSString
        if let slidesData = NSData(
            contentsOfFile: documentsPath.stringByAppendingPathComponent("slides")),
            optionalSlides = Slide.slidesfromData(slidesData) {
            slides = optionalSlides.flatMap { $0 }
        }
        watchConnectivitySession.delegate = self
        watchConnectivitySession.activateSession()
        if watchConnectivitySession.reachable {
            sendSlidesToWatch(watchConnectivitySession)
        }
    }

    // MARK: Connectivity Updates

    private func setupConnectivityObserver() {
        multipeerClient.onStateChange = { state, peerID in
            let client = self.multipeerClient
            let borderColor: UIColor
            switch state {
            case .NotConnected:
                borderColor = .redColor()
                if let session = client.session where session.connectedPeers.count == 0 {
                    client.browser?.invitePeer(peerID, toSession: session, withContext: nil,
                        timeout: 30)
                }
            case .Connecting:
                borderColor = .orangeColor()
            case .Connected:
                borderColor = .greenColor()
            }
            dispatch_async(dispatch_get_main_queue()) {
                self.collectionView?.layer.borderColor = borderColor.CGColor
            }
        }
    }

    func sessionReachabilityDidChange(session: WCSession) {
        sendSlidesToWatch(session)
    }

    private func sendSlidesToWatch(session: WCSession) {
        guard session.reachable, let slides = slides else { return }

        let scaledSlides = slides.flatMap({ $0.dictionaryRepresentation })
        let data = NSKeyedArchiver.archivedDataWithRootObject(scaledSlides)
        session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    func session(session: WCSession, didReceiveMessage message: [String : AnyObject],
        replyHandler: ([String : AnyObject]) -> Void) {
            replyHandler(message)
            dispatch_async(dispatch_get_main_queue()) { [unowned self] in
                if let row = message["row"] as? CGFloat,
                    collectionView = self.collectionView,
                    layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
                        collectionView.contentOffset.x =
                            layout.itemSize.width * row
                        self.multipeerClient.sendString("\(row)")
                }
            }
    }

    // MARK: UI

    private func setupUI() {
        setupCollectionView()
        setupInfoLabel()
    }

    private func setupCollectionView() {
        collectionView?.registerClass(Cell.self, forCellWithReuseIdentifier: "cell")
        collectionView?.pagingEnabled = true
        collectionView?.showsHorizontalScrollIndicator = false
        collectionView?.layer.borderColor = UIColor.redColor().CGColor
        collectionView?.layer.borderWidth = 2
        setCollectionViewItemSize(view.bounds.size)
    }

    private func setupInfoLabel() {
        infoLabel.userInteractionEnabled = false
        infoLabel.numberOfLines = 0
        infoLabel.text = "Thanks for installing DeckRocket!\n\n" +
            "To get started, follow these simple steps:\n\n" +
            "1. Open a presentation in Deckset on your Mac.\n" +
            "2. Launch DeckRocket on your Mac.\n" +
            "3. Click the DeckRocket menu bar icon and select \"Send Slides\".\n\n" +
            "From there, swipe on your phone to control your Deckset slides, " +
            "tap the screen to toggle between current slide and notes view, and finally: " +
            "keep an eye on the color of the border! Red means the connection was lost. " +
            "Green means everything should work!"
        infoLabel.textColor = UIColor.whiteColor()
        view.addSubview(infoLabel)

        constrain(infoLabel, view) {
            $0.left   == $1.left  + 20
            $0.right  == $1.right - 20
            $0.top    == $1.top
            $0.bottom == $1.bottom
        }
    }

    // MARK: Collection View

    override func collectionView(collectionView: UICollectionView,
                                 numberOfItemsInSection section: Int) -> Int {
        return slides?.count ?? 0
    }

    override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath
                                 indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier("cell",
            forIndexPath: indexPath) as! Cell // swiftlint:disable:this force_cast
        cell.imageView.image = slides?[indexPath.item].image
        cell.notesView.text = slides?[indexPath.item].notes
        if indexPath.item + 1 < slides?.count {
            cell.nextSlideView.image = slides?[indexPath.item + 1].image
        } else {
            cell.nextSlideView.image = nil
        }
        return cell
    }

    // MARK: UIScrollViewDelegate

    private func currentSlide() -> UInt {
        guard let collectionView = collectionView,
            layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
                return 0
        }
        return UInt(round(collectionView.contentOffset.x / layout.itemSize.width))
    }

    override func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        multipeerClient.sendString("\(currentSlide())")
    }

    // MARK: Rotation

    private func setCollectionViewItemSize(size: CGSize) {
        (collectionView?.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = size
    }

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator
                                           coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
        let current = currentSlide()
        UIView.animateWithDuration(coordinator.transitionDuration()) {
            self.collectionView?.contentOffset.x = CGFloat(current) * size.width
        }
        setCollectionViewItemSize(size)
    }
}
