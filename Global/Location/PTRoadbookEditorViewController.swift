//
//  PTRoadbookEditorViewController.swift
//  CrazyDashboard
//
//  EN: A small map-backed editor for ordered Roadbook waypoints.
//  ES: Un editor pequeño respaldado por mapa para puntos ordenados de Roadbook.
//  中文：基于地图的轻量 Roadbook 有序路点编辑器。
//

import AMapNaviKit
import CoreLocation
import UIKit
import PooTools

@MainActor
final class PTRoadbookEditorViewController: PTMotoBaseViewController {
    private let manager = PTCustomRouteManager.shared
    private let originalRoadbook: PTRoadbook?
    private var roadbookName: String
    private let coordinateSystem: PTRoadbookCoordinateSystem
    private let sourceFileName: String?
    private let createdAt: Date
    private var waypoints: [PTCruiseWaypoint]

    private let mapView = MAMapView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let addCurrentLocationButton = UIButton(type: .system)
    private let addCoordinateButton = UIButton(type: .system)
    private var saveTask: Task<Void, Never>?

    init(roadbook: PTRoadbook? = nil) {
        self.originalRoadbook = roadbook
        self.roadbookName = roadbook?.name ?? "ADV Roadbook"
        self.coordinateSystem = roadbook?.coordinateSystem ?? .wgs84
        self.sourceFileName = roadbook?.sourceFileName
        self.createdAt = roadbook?.createdAt ?? Date()
        self.waypoints = roadbook?.waypoints ?? []
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = originalRoadbook == nil
            ? localized("roadbook_create")
            : localized("roadbook_edit")
        view.backgroundColor = .systemGroupedBackground
        let nameButton = UIButton(type: .system)
        nameButton.setTitle(roadbookName, for: .normal)
        nameButton.setTitleColor(PTDashboardConfig.shared.appMainColor, for: .normal)
        nameButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        nameButton.addTarget(self, action: #selector(renameRoadbook), for: .touchUpInside)
        navigationItem.titleView = nameButton
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: localized("roadbook_save"), style: .done, target: self, action: #selector(saveRoadbook)),
            UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(toggleEditing))
        ]
        configureMap()
        configureTable()
        configureButtons()
        updateMap()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveTask?.cancel()
    }

    private func configureMap() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.mapType = .standardNight
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.logoEnable = false
        mapView.delegate = self
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.heightAnchor.constraint(equalToConstant: 230)
        ])
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView(frame: .zero)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: mapView.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureButtons() {
        configureButton(addCurrentLocationButton, title: localized("roadbook_add_current_location"), color: .systemBlue)
        configureButton(addCoordinateButton, title: localized("roadbook_add_coordinate"), color: .systemTeal)
        addCurrentLocationButton.addTarget(self, action: #selector(addCurrentLocation), for: .touchUpInside)
        addCoordinateButton.addTarget(self, action: #selector(addCoordinate), for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [addCurrentLocationButton, addCoordinateButton])
        header.axis = .horizontal
        header.spacing = 8
        header.distribution = .fillEqually
        header.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 46)
        tableView.tableHeaderView = header
    }

    private func configureButton(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = color.withAlphaComponent(0.85)
        button.layer.cornerRadius = 8
    }

    @objc private func toggleEditing() {
        tableView.setEditing(!tableView.isEditing, animated: true)
    }

    @objc private func renameRoadbook() {
        let alert = UIAlertController(
            title: localized("roadbook_rename"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.text = self.roadbookName
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("roadbook_save"), style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let value = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return }
            roadbookName = String(value.prefix(80))
            (navigationItem.titleView as? UIButton)?.setTitle(roadbookName, for: .normal)
        })
        present(alert, animated: true)
    }

    @objc private func addCurrentLocation() {
        guard let location = PTLocationEngine.shared.lastLocation,
              location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite else {
            showMessage(localized("roadbook_location_unavailable"))
            return
        }
        appendWaypoint(
            coordinate: location.coordinate,
            instruction: localized("roadbook_current_location")
        )
    }

    @objc private func addCoordinate() {
        let alert = UIAlertController(
            title: localized("roadbook_add_coordinate"),
            message: localized("roadbook_coordinate_hint"),
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = self.localized("roadbook_latitude"); $0.keyboardType = .decimalPad }
        alert.addTextField { $0.placeholder = self.localized("roadbook_longitude"); $0.keyboardType = .decimalPad }
        alert.addTextField { $0.placeholder = self.localized("roadbook_instruction") }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("roadbook_add"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let latitudeText = alert?.textFields?[0].text,
                  let longitudeText = alert?.textFields?[1].text,
                  let latitude = Double(latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let longitude = Double(longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else {
                self?.showMessage(self?.localized("roadbook_invalid_coordinate") ?? "roadbook_invalid_coordinate")
                return
            }
            let instruction = alert?.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.appendWaypoint(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                instruction: instruction?.isEmpty == false ? instruction! : self.localized("roadbook_waypoint")
            )
        })
        present(alert, animated: true)
    }

    private func appendWaypoint(coordinate: CLLocationCoordinate2D, instruction: String) {
        waypoints.append(
            PTCruiseWaypoint(
                coordinate: coordinate,
                instruction: instruction,
                maneuverCode: PTManeuverMap.straight
            )
        )
        tableView.reloadData()
        updateMap()
    }

    @objc private func saveRoadbook() {
        guard saveTask == nil else { return }
        let trimmedName = roadbookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showMessage(localized("roadbook_name_required"))
            return
        }
        guard waypoints.count >= 2 else {
            showMessage(localized("roadbook_minimum_waypoints"))
            return
        }

        let roadbook = PTRoadbook(
            id: originalRoadbook?.id ?? UUID(),
            name: trimmedName,
            coordinateSystem: coordinateSystem,
            sourceFileName: sourceFileName,
            waypoints: waypoints,
            createdAt: createdAt,
            updatedAt: Date()
        )
        saveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await manager.saveRoadbook(roadbook)
                navigationController?.popViewController(animated: true)
            } catch {
                showMessage(error.localizedDescription)
            }
            saveTask = nil
        }
    }

    private func updateMap() {
        mapView.removeAnnotations(mapView.annotations)
        let annotations = waypoints.enumerated().map { index, waypoint in
            let annotation = MAPointAnnotation()
            annotation.coordinate = waypoint.coordinate
            annotation.title = "\(index + 1). \(waypoint.instruction)"
            return annotation
        }
        mapView.addAnnotations(annotations)
        guard let first = waypoints.first else { return }
        mapView.setCenter(first.coordinate, animated: false)
        mapView.setZoomLevel(12, animated: false)
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: pt_Title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default))
        present(alert, animated: true)
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }
}

extension PTRoadbookEditorViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        waypoints.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PTRoadbookEditorCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "PTRoadbookEditorCell")
        let waypoint = waypoints[indexPath.row]
        cell.textLabel?.text = "\(indexPath.row + 1). \(waypoint.instruction)"
        cell.detailTextLabel?.text = String(format: "%.5f, %.5f", waypoint.latitude, waypoint.longitude)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let waypoint = waypoints.remove(at: sourceIndexPath.row)
        waypoints.insert(waypoint, at: destinationIndexPath.row)
        updateMap()
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        waypoints.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        updateMap()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        mapView.setCenter(waypoints[indexPath.row].coordinate, animated: true)
        mapView.setZoomLevel(15, animated: true)
    }
}

extension PTRoadbookEditorViewController: MAMapViewDelegate {}
