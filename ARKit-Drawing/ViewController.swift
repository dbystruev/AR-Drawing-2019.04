import ARKit

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    
    let configuration = ARWorldTrackingConfiguration()
    
    /// Mimimim distance between nearby points (in 2D coordinates)
    let touchDistanceThreshold = CGFloat(80)
    
    /// Coordinates of last placed point
    var lastObjectPlacedPoint: CGPoint?
    
    /// Node selected by user
    var selectedNode: SCNNode?
    
    /// Nodes placed by the user
    var placedNodes = [SCNNode]()
    
    /// Visualization planes placed when detecting planes
    var planeNodes = [SCNNode]()
    
    /// Defines whether plane visualisation is shown
    var showPlaneOverlay = false {
        didSet {
            for node in planeNodes {
                node.isHidden = !showPlaneOverlay
            }
        }
    }
    
    enum ObjectPlacementMode {
        case freeform, plane, image
    }
    
    var objectMode: ObjectPlacementMode = .freeform {
        didSet {
            reloadConfiguration()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfiguration()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    @IBAction func changeObjectMode(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            objectMode = .freeform
            showPlaneOverlay = false
        case 1:
            objectMode = .plane
            showPlaneOverlay = true
        case 2:
            objectMode = .image
            showPlaneOverlay = false
        default:
            break
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOptions" {
            let optionsViewController = segue.destination as! OptionsContainerViewController
            optionsViewController.delegate = self
        }
    }
}

extension ViewController: OptionsViewControllerDelegate {
    
    /// Called when user selects an object
    ///
    /// - Parameter node: SCNNode of an object selected by user
    func objectSelected(node: SCNNode) {
        dismiss(animated: true, completion: nil)
        selectedNode = node
    }
    
    func togglePlaneVisualization() {
        dismiss(animated: true, completion: nil)
        showPlaneOverlay.toggle()
    }
    
    func undoLastObject() {
        
    }
    
    func resetScene() {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - Touches
extension ViewController {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let touch = touches.first else { return }
        guard let node = selectedNode else { return }
        
        switch objectMode {
        case .freeform:
            addNodeInFront(node)
        case .plane:
            let point = touch.location(in: sceneView)
            addNode(node, to: point)
        case .image:
            break
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard let selectedNode = selectedNode else { return }
        guard let touch = touches.first else { return }
        guard let lastTouchPoint = lastObjectPlacedPoint else { return }
        
        let newTouchPoint = touch.location(in: sceneView)
        
        let deltaX = newTouchPoint.x - lastTouchPoint.x
        let deltaY = newTouchPoint.y - lastTouchPoint.y
        let distanceSquare = deltaX * deltaX + deltaY * deltaY
        
        guard touchDistanceThreshold * touchDistanceThreshold < distanceSquare else {
            return
        }
        
        switch objectMode {
        case .freeform:
            break
        case .image:
            break
        case .plane:
            addNode(selectedNode, to: newTouchPoint)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        lastObjectPlacedPoint = nil
    }
}

// MARK: - Placement Methods
extension ViewController {
    /// Adds a node to parent node
    ///
    /// - Parameters:
    ///   - node: nodes which will to be added
    ///   - parentNode: parent node to which the node to be added
    func addNode(_ node: SCNNode, to parentNode: SCNNode, isFloor: Bool = false) {
        let cloneNode = isFloor ? node : node.clone()
        parentNode.addChildNode(cloneNode)
        
        if isFloor {
            planeNodes.append(cloneNode)
        } else {
            placedNodes.append(cloneNode)
        }
    }
    
    /// Adds a node using a point at the screen
    ///
    /// - Parameters:
    ///   - node: selected node to add
    ///   - point: point at the screen to use
    func addNode(_ node: SCNNode, to point: CGPoint) {
        let results = sceneView.hitTest(point, types: [.existingPlaneUsingExtent])
        
        guard let match = results.first else { return }
        
        let transform = match.worldTransform
//        node.simdTransform = transform
        
        let translate = transform.columns.3
        let x = translate.x
        let y = translate.y
        let z = translate.z
        node.position = SCNVector3(x, y, z)
        
        addNodeToSceneRoot(node)
        lastObjectPlacedPoint = point
    }
    
    /// Places object defined by node at 20 cm before the camera
    ///
    /// - Parameter node: SCNNode to place in scene
    func addNodeInFront(_ node: SCNNode) {
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        var translation = matrix_identity_float4x4
        translation.columns.3.z = -0.2
        node.simdTransform = matrix_multiply(currentFrame.camera.transform, translation)
        
        addNodeToSceneRoot(node)
    }
    
    /// Clones and adds an object defined by node to scene root
    ///
    /// - Parameter node: SCNNode which will be added
    func addNodeToSceneRoot(_ node: SCNNode) {
        let rootNode = sceneView.scene.rootNode
        addNode(node, to: rootNode)
    }
    
    /// Creates visualization plane
    ///
    /// - Parameter planeAnchor: anchor attached to the plane
    /// - Returns: node of created visualization plane
    func createFloor(planeAnchor: ARPlaneAnchor) -> SCNNode {
        let extent = planeAnchor.extent
        let geometry = SCNPlane(width: CGFloat(extent.x), height: CGFloat(extent.z))
        geometry.firstMaterial?.diffuse.contents = UIColor.blue
        
        let node = SCNNode(geometry: geometry)
        
        node.eulerAngles.x = -.pi / 2
        node.opacity = 0.25
        
        return node
    }
    
    /// Plane node AR anchor has been added to the scene
    ///
    /// - Parameters:
    ///   - node: node which was added
    ///   - anchor: AR plane anchor which defines the plane found
    func nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        let floor = createFloor(planeAnchor: anchor)
        floor.isHidden = !showPlaneOverlay
        addNode(floor, to: node, isFloor: true)
    }
    
    /// Image node AR anchor has been added to the scene
    ///
    /// - Parameters:
    ///   - node: node which was added
    ///   - anchor: AR image anchor which defines the image found
    func nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor) {
        guard let selectedNode = selectedNode else { return }
        
        addNode(selectedNode, to: node)
    }
}

// MARK: - ARSCNViewDelegate
extension ViewController {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        print(#function, #line)
        
        if let planeAnchor = anchor as? ARPlaneAnchor {
            nodeAdded(node, for: planeAnchor)
        } else if let imageAnchor = anchor as? ARImageAnchor {
            nodeAdded(node, for: imageAnchor)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        guard let planeNode = node.childNodes.first else { return }
        guard let plane = planeNode.geometry as? SCNPlane else { return }
        
        let center = planeAnchor.center
        planeNode.position = SCNVector3(center.x, 0, center.z)
        
        let extent = planeAnchor.extent
        plane.width = CGFloat(extent.x)
        plane.height = CGFloat(extent.z)
    }
}

// MARK: - Configuration Methods
extension ViewController {
    func reloadConfiguration() {
        configuration.planeDetection = .horizontal
        
        let images = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil)
        
        configuration.detectionImages = objectMode == .image ? images : nil
        
        sceneView.session.run(configuration)
    }
}
