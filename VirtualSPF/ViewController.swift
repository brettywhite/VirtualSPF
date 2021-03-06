//
//  ViewController.swift
//  VirtualSPF
//
//  Created by brettywhite on 7/26/15.
//  Copyright (c) 2017 brettywhite. All rights reserved.
//

import UIKit
import Alamofire
import SwiftyJSON
import CoreLocation
import MBProgressHUD
import LMGaugeView
import Refresher

class ViewController: BaseViewController, WeatherDelegate, LMGaugeViewDelegate, CLLocationManagerDelegate, UITableViewDelegate, UITableViewDataSource {

    var locationManager: CLLocationManager!
    var seenError: Bool = false
    var locationFixAchieved: Bool = false
    var locationStatus: NSString = VSPFConstants.NotStarted as NSString
    var weatherArray: JSON = [:]
    var cell: MainCell?
    var state: NetworkState = .finished
    var guage: LMGaugeView!

    //outlets
    @IBOutlet var tableView: UITableView!
    @IBOutlet weak var infoBtn: UIBarButtonItem?
    @IBOutlet weak var settingsBTN: UIButton?

    class ViewController {
        init () {}
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        initLocationManager()
        initGuage()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    internal func initGuage() {
        //print(UIDevice.current.modelName)
        if UIDevice.current.modelName == "iPhone10,3" || UIDevice.current.modelName == "iPhone10,6" ||
           UIDevice.current.modelName == "iPhone11,2" || UIDevice.current.modelName == "iPhone11,8" ||
           UIDevice.current.modelName == "iPhone11,4" || UIDevice.current.modelName == "x86_64" {
           guage = LMGaugeView.init(frame: rect(0, 10, self.view.frame.size.width, self.view.frame.size.height-650))
        } else {
        guage = LMGaugeView.init(frame: rect(0, 13, self.view.frame.size.width, self.view.frame.size.height-490))
        }
        guage.minValue = 0
        guage.maxValue = 11
        guage.unitOfMeasurement = "Current UV Index"
        self.view.addSubview(guage)
    }

    // MARK: Response Handeling
    fileprivate func iterateResponse(_ data: JSON) {
        let current = data["currently"]["uvIndex"].floatValue
        guage.value = CGFloat(current)
        weatherArray = data["hourly"]["data"]
        weatherArray.arrayObject?.remove(at: 0)
        self.view.backgroundColor = ColorChooser.decideColor(Int(current))
        tableView.reloadData()
        tableView.addPullToRefreshWithAction {
            self.initLocationManager()
            self.tableView.stopPullToRefresh()
        }
    }

    // MARK: Table Stuff
    internal func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.weatherArray.count
    }

    internal func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        cell = tableView.dequeueReusableCell(withIdentifier: "mainCellID", for: indexPath) as? MainCell

        let uvi = weatherArray[indexPath.row]["uvIndex"]
        let hour = weatherArray[indexPath.row]["time"]
        let cellTime: String = "\(hour)"
        let cellUVI: String = "\(uvi)"

        self.cell!.selectionStyle = UITableViewCell.SelectionStyle.none
        self.cell!.uviLabel.text = cellUVI
        self.cell!.timeLabel.text = TimeConverter.convertTime(unixtime: cellTime)

        let uvint: Int = Int(cellUVI)!
        cell!.backgroundColor = ColorChooser.decideColor(uvint)

        return cell!
    }

    internal func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        //println("You selected cell #\(indexPath.row)!")
    }

    /*internal func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Upcoming UV indexes:"
    }*/

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

        if segue.identifier == "explainSegue" {
            let row = self.tableView.indexPathForSelectedRow!.row
            let uvi = weatherArray[row]["uvIndex"]
            let cellUVI: String = "\(uvi)"
            let explainationViewController = (segue.destination as! ExplainationView)
            explainationViewController.UVValue = cellUVI
        }
    }

    func displayHUD() {
        let hud = MBProgressHUD.showAdded(to: self.view, animated: true)
        hud?.labelText = VSPFConstants.FindingSun
    }

    func hideHUD() {
        MBProgressHUD.hideAllHUDs(for: self.view, animated: true)
    }

    // MARK: - Delegate Functions
    func didChangeState(_ newState: NetworkState, data: JSON) {
        state = newState

        switch newState {
        case .searching:
            displayHUD()
        case .finished:
            hideHUD()
            iterateResponse(data)
        case .error:
            hideHUD()
        }
    }
}

// MARK: Location Stuff
extension ViewController {

    func initLocationManager() {
        seenError = false
        locationFixAchieved = false
        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
        }

        if CLLocationManager.authorizationStatus() == .notDetermined {

            locationManager.requestWhenInUseAuthorization()

        } else if CLLocationManager.authorizationStatus() == .denied {

            settingsBTN?.isHidden = false

            let alertController = UIAlertController(
                title: VSPFConstants.LocationDisabled,
                message: VSPFConstants.LocationMessage,
                preferredStyle: .alert)

            let cancelAction = UIAlertAction(title: VSPFConstants.Cancel, style: .cancel, handler: nil)
            alertController.addAction(cancelAction)

            let openAction = UIAlertAction(title: VSPFConstants.OpenSettings, style: .default) { (_) in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            alertController.addAction(openAction)

            self.present(alertController, animated: true, completion: nil)
        }

        locationManager.startUpdatingLocation()

        let hud = MBProgressHUD.showAdded(to: self.view, animated: true)
        hud?.labelText = VSPFConstants.FindingSun
    }

    internal func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

        // only do this if we have a location fix
        if locationFixAchieved == false {

            settingsBTN?.isHidden = true
            locationFixAchieved = true

            let locationArray = locations as NSArray
            let locationObj = locationArray.lastObject as! CLLocation
            let coord = locationObj.coordinate

            locationManager.stopUpdatingLocation()
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let geoCoder = CLGeocoder()

            geoCoder.reverseGeocodeLocation(location, completionHandler: { (placemarks, _) -> Void in
                let placeArray = placemarks as [CLPlacemark]?

                var placeMark: CLPlacemark!
                placeMark = placeArray?[0]

                if let city = placeMark.addressDictionary?["City"] as? NSString {
                    self.navigationItem.title = "VirtualSPF - \(city)"
                }
            })

            WeatherModel.getWeather(location)
        }
    }

    internal func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {

        locationManager.stopUpdatingLocation()
        MBProgressHUD.hideAllHUDs(for: self.view, animated: true)
        print("Error with location manager")
    }

    internal func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {

        switch CLLocationManager.authorizationStatus() {

        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case  .restricted, .denied:
            settingsBTN?.isHidden = false
            //if denied, show alert why it wont work without permission
            let alertController = UIAlertController(
                title: VSPFConstants.LocationDisabled,
                message: VSPFConstants.LocationMessage,
                preferredStyle: .alert)

            let cancelAction = UIAlertAction(title: VSPFConstants.Cancel, style: .cancel, handler: nil)
            alertController.addAction(cancelAction)
            let openAction = UIAlertAction(title: VSPFConstants.OpenSettings, style: .default) { (_) in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            alertController.addAction(openAction)

            self.present(alertController, animated: true, completion: nil)

        default: break
        }
    }
}

// MARK: other stuff
extension ViewController {

    @IBAction func openSettings(_ sender: UIButton) {
        let alertController = UIAlertController(
            title: VSPFConstants.LocationDisabled,
            message: VSPFConstants.LocationMessage,
            preferredStyle: .alert)

        let cancelAction = UIAlertAction(title: VSPFConstants.Cancel, style: .cancel, handler: nil)
        alertController.addAction(cancelAction)

        let openAction = UIAlertAction(title: VSPFConstants.OpenSettings, style: .default) { (_) in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        alertController.addAction(openAction)
        self.present(alertController, animated: true, completion: nil)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        return CGRect(x: x, y: y, width: width, height: height)
    }

}

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
