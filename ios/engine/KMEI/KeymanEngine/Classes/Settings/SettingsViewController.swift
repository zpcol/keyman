//
//  SettingsViewController.swift
//  KeymanEngine
//
//  Created by Randy Boring on 5/13/19.
//  Copyright © 2019 SIL International. All rights reserved.
//

import UIKit

open class SettingsViewController: UITableViewController {
  private var itemsArray = [[String: String]]()
  private var userLanguages: [String: Language] = [:]

  override open func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    
    loadUserLanguages()
    log.info("didAppear: SettingsViewController (actually willAppear)")
 }
  
  override open func viewDidLoad() {
    super.viewDidLoad()
    
    title = "Keyman Settings"
    let doneButton = UIBarButtonItem(title: "Done", style: .plain, target: self,
                                     action: #selector(self.doneClicked))
    navigationItem.leftBarButtonItem = doneButton

    navigationController?.toolbar?.barTintColor = UIColor(red: 0.5, green: 0.75,
                                                          blue: 0.25, alpha: 0.9)
  }
  
  @objc func doneClicked(_ sender: Any) {
    Manager.shared.dismissKeyboardPicker(self)
  }
  
  open func launchSettings(launchingVC: UIViewController, sender: Any?) -> Void {
    let sb : UIStoryboard = UIStoryboard(name: "Settings", bundle: nil)
    if let vc = sb.instantiateInitialViewController() {
      launchingVC.present(vc, animated: true, completion: {
        log.info("presented settings")
      })
    }
  }
//
//  convenience init() {
//    self.init(style: UITableViewStyle.grouped)
//  }
  
  init(/*storage: Storage*/) {
//    self.storage = storage
    super.init(nibName: nil, bundle: nil)
    
    itemsArray = [[String: String]]()
    itemsArray.append([
      "title": "Languages Settings",
      "subtitle": "0", //count of installed languages as string
      "reuseid" : "language"
      ])
    
    itemsArray.append([
      "title": "Show Banner",
      "subtitle": "",
      "reuseid" : "showbanner"
      ])
    
    itemsArray.append([
      "title": "Show 'Get Started' at startup",
      "subtitle": "",
      "reuseid" : "showgetstarted"
      ])
    _ = view
  }

  required public init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

    // MARK: - Table view data source

  override open func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

  override open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return 3
    }
  
  public func frameAtRightOfCell(cell cellFrame: CGRect, controlSize: CGSize) -> CGRect {
    let rightOffset = cellFrame.size.width
    let switchWidth: CGFloat = 20
    let switchX = rightOffset - switchWidth
    let switchHeight = controlSize.height
    let cellSwitchHeightDiff = cellFrame.size.height - switchHeight
    let switchY = cellFrame.origin.y + 0.5 * cellSwitchHeightDiff
    
    let switchFrame = CGRect(x: switchX,
                             y: switchY,
                             width: switchWidth,
                             height: cellFrame.size.height)
    return switchFrame
  }

  override open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cellIdentifier = itemsArray[indexPath.row]["reuseid"]
    if let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier!) {
      return cell
    }
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: cellIdentifier)
    cell.selectionStyle = .none
    
    switch(cellIdentifier) {
      case "languages":
        cell.accessoryType = .disclosureIndicator
      case "showbanner":
        cell.accessoryType = .none
        let showBannerSwitch = UISwitch()
        let switchFrame = frameAtRightOfCell(cell: cell.frame, controlSize: showBannerSwitch.frame.size)
        showBannerSwitch.frame = switchFrame
        showBannerSwitch.isOn = false //TODO: find the setting this is to show!
        showBannerSwitch.addTarget(self, action: #selector(self.bannerSwitchValueChanged),
                                      for: .valueChanged)
        cell.addSubview(showBannerSwitch)
      case "showgetstarted":
        cell.accessoryType = .none
        let dontShowAgainSwitch = UISwitch()
//        let rightOffset = cell.frame.size.width
//        let switchWidth: CGFloat = 20
//        let switchX = rightOffset - switchWidth
//        let dontShowAgainSwitch = UISwitch()
//        let switchHeight = dontShowAgainSwitch.frame.size.height
//        let cellSwitchHeightDiff = cell.frame.size.height - switchHeight
//        let switchY = cell.frame.origin.y + 0.5 * cellSwitchHeightDiff

//        let switchFrame = CGRect(x: switchX,
//                                 y: switchY,
//                                 width: switchWidth,
//                                 height: cell.frame.size.height)
        let switchFrame = frameAtRightOfCell(cell: cell.frame, controlSize: dontShowAgainSwitch.frame.size)
        dontShowAgainSwitch.frame = switchFrame
        dontShowAgainSwitch.isOn = dontShowGetStarted
        dontShowAgainSwitch.addTarget(self, action: #selector(self.showGetStartedSwitchValueChanged),
                                      for: .valueChanged)
        cell.addSubview(dontShowAgainSwitch)

      default:
        log.error("unknown cellIdentifier(\"\(cellIdentifier ?? "EMPTY")\")")
        cell.accessoryType = .none
    }
    
    return cell
  }
  
  @objc func bannerSwitchValueChanged(_ sender: Any) {
    let userData = Storage.active.userDefaults
    if let toggle = sender as? UISwitch {
      // actually this should call into KMW, which controls the banner
      userData.set(toggle.isOn, forKey: "ShouldShowBanner") //???
      userData.synchronize()
    }
  }
  
  @objc func showGetStartedSwitchValueChanged(_ sender: Any) {
    let userData = Storage.active.userDefaults
    if let toggle = sender as? UISwitch {
      userData.set(toggle.isOn, forKey: "ShouldShowGetStarted")
      userData.synchronize()
    }
  }
  
  private var dontShowGetStarted: Bool {
    let userData = Storage.active.userDefaults
    return !userData.bool(forKey: "ShouldShowGetStarted")
  }

  override open func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    cell.accessoryType = .none
    cell.textLabel?.text = itemsArray[indexPath.row]["title"]
    cell.detailTextLabel?.text = itemsArray[indexPath.row]["subtitle"]
    cell.tag = indexPath.row
    cell.isUserInteractionEnabled = true

    if indexPath.row == 0 {
      cell.accessoryType = .disclosureIndicator
    } else {
      cell.textLabel?.isEnabled = true
      cell.detailTextLabel?.isEnabled = false
    }

  }
  
  // In a xib-based application, navigation from a table can be handled in -tableView:didSelectRowAtIndexPath:
  override open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.cellForRow(at: indexPath)?.isSelected = false
    performAction(for: indexPath)
  }
  
  override open func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
    performAction(for: indexPath)
  }
  
  private func performAction(for indexPath: IndexPath) {
    switch indexPath.section {
    case 0:
      showLanguages()
    default:
      break
    }
  }

    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
  override open func prepare(for segue: UIStoryboardSegue, sender: Any?) {
      log.info("prepare for segue")
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
  }
  
  // MARK: - language access -
  private func installed2API(_ installedList: [InstallableLexicalModel]) -> [LexicalModel] {
    var returnList = [LexicalModel]()
    for ilm in installedList {
      returnList.append(LexicalModel(id: ilm.id, name: ilm.name, license: "", version: ilm.version, languages: [], authorName: "", fileSize: 0, filename: "no filename", sourcePath: nil, authorEmail: nil, description: nil, packageFileSize: 0, packageFilename: "", packageIncludes: nil, isDefault: false, lastModified: nil, minKeymanVersion: nil))
    }
    return returnList
  }
  
  // MARK: - language access -
  private func loadUserLanguages() {
    //iterate the list of installed languages and save their names
    // Get keyboards list if it exists in user defaults, otherwise create a new one
    let userDefaults = Storage.active.userDefaults
    let userKeyboards = userDefaults.userKeyboards ?? []

    var keyboardLanguages = [String: Language]()
    for k in userKeyboards {
      let l = k.languageID
      var kbds: [Keyboard]
      if let existingLanguage = keyboardLanguages[l] {
        kbds = existingLanguage.keyboards ?? []
        kbds.append(Keyboard(name: k.name, id: k.id, filename: "no filename", isDefault: nil, isRTL: k.isRTL, lastModified: Date(), fileSize: 0, version: k.version, languages: nil, font: nil, oskFont: nil))
      } else {
        kbds = [Keyboard(name: k.name, id: k.id, filename: "no filename", isDefault: nil, isRTL: k.isRTL, lastModified: Date(), fileSize: 0, version: k.version, languages: nil, font: nil, oskFont: nil)]
      }
      let userDefaults = Storage.active.userDefaults
      let lmListInstalled: [InstallableLexicalModel] = userDefaults.userLexicalModels(forLanguage: k.languageID) ?? []
      let lmList = installed2API(lmListInstalled)
      keyboardLanguages[l] = Language(name: k.languageName, id: k.languageID, keyboards: kbds, lexicalModels: lmList, font: nil, oskFont: nil)
    }
    // there shouldn't be any lexical models for languages that don't have a keyboard installed
    //  but check
    let userLexicalModels = userDefaults.userLexicalModels ?? []
    for lm in userLexicalModels {
      let l = lm.languageID
      if let langName = keyboardLanguages[l]?.name {
        log.info("keyboard language \(l) \(langName) has lexical model")
      } else {
        log.error("lexical model language \(l) has no keyboard installed!")
      }
    }

    userLanguages = keyboardLanguages
    itemsArray[0]["subtitle"] = "\(userLanguages.count) languages installed"
  }
  
  public func setIsDoneButtonEnabled(_ nc: UINavigationController, _ value: Bool) {
    let doneOrCancel = value
    if doneOrCancel {
      let doneButton = UIBarButtonItem(title: "Done", style: .plain, target: self,
                                       action: nil /* #selector(self.doneClicked) */ )
      nc.navigationItem.leftBarButtonItem = doneButton
    } else {
      let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self,
                                         action: nil /* #selector(self.cancelClicked) */ )
      nc.navigationItem.leftBarButtonItem = cancelButton
    }
  }

  func showLanguages() {
    let vc = InstalledLanguagesViewController(userLanguages)
    if let nc = navigationController {
      nc.pushViewController(vc, animated: true)
      setIsDoneButtonEnabled(nc, true)
    } else {
      log.error("no navigation controller for showing languages???")
    }
  }
  
}
