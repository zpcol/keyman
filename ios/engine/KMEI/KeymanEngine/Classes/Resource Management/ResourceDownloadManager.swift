//
//  ResourceDownloadManager.swift
//  KeymanEngine
//
//  Created by Joshua Horton on 8/15/19.
//  Copyright © 2019 SIL International. All rights reserved.
//

import Foundation

// One half of the resource management puzzle - this part generates download and update requests at the demand
// of app UI and submits them to the actual 'download manager', the ResourceDownloadQueue.
//
// This will be the public face of resource download management in KMEI, while the other half is private and
// only accessible within the library.
public class ResourceDownloadManager {
  // internal b/c testing access.
  internal var session: URLSession
  internal var downloader: ResourceDownloadQueue
  private var isDidUpdateCheck = false

  public typealias CompletionHandler<Resource: LanguageResource> = (Resource.Package?, Error?) -> Void where Resource.Package: TypedKeymanPackage<Resource>
  public typealias BatchCompletionHandler = () -> Void
  internal typealias InternalBatchCompletionHandler = (CompositeBatch) -> Void
  
  public static let shared = ResourceDownloadManager()

  internal init() {
    session = URLSession.shared
    downloader = ResourceDownloadQueue()
  }

  // Intended only for use in testing!
  internal init(session: URLSession, autoExecute: Bool) {
    self.session = session
    downloader = ResourceDownloadQueue(session: session, autoExecute: autoExecute)
  }
  
  // MARK: - Common functionality
  
  private func fetchHandler(for resourceType: LanguageResourceType?, _ completionHandler: @escaping () -> Void)
                            -> (_ error: Error?) -> Void {
    return { error in
      if let error = error {
        // TODO:  Connect to an error handler (or just render appropriate text) based on the resource type.
        self.resourceDownloadFailed(for: [] as [InstallableKeyboard], with: error)
      } else {
        log.info("Fetched repository. Continuing with download.")
        completionHandler()
      }
    }
  }
  
  // MARK - Downloading keyboards
  
  private func getInstallableKeyboardMetadata(withID keyboardID: String, languageID: String) -> InstallableKeyboard? {
    // Grab info for the relevant API version of the keyboard.
    guard let keyboard = Manager.shared.apiKeyboardRepository.installableKeyboard(withID: keyboardID, languageID: languageID)
    else {
      let message = "Keyboard not found with id: \(keyboardID), languageID: \(languageID)"
      let error = NSError(domain: "Keyman", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: message])
      self.resourceDownloadFailed(for: [] as [InstallableKeyboard], with: error)
      return nil
    }
    
    return keyboard
  }
  
  // We return the batch instance to indicate success.  Also, in case we decide to implement Promises based on batch completion,
  // since this will expose the generated Promise for the caller's use.
  private func downloadKeyboardCore(withMetadata keyboards: [InstallableKeyboard],
                                    asActivity activity: DownloadActivityType,
                                    withFilename filename: String,
                                    withOptions options: Options,
                                    completionBlock: CompletionHandler<InstallableKeyboard>? = nil) -> DownloadBatch<InstallableKeyboard.FullID>? {
    var startClosure: (() -> Void)? = nil
    if activity != .update {
      startClosure = self.resourceDownloadStartClosure(for: keyboards)
    }
    let completionClosure = self.resourceDownloadCompletionClosure(for: keyboards, handler: completionBlock)
    if let dlBatch = buildKeyboardDownloadBatch(for: keyboards[0],
                                                withFilename: filename,
                                                asActivity: activity,
                                                withOptions: options,
                                                startBlock: startClosure,
                                                completionBlock: completionClosure) {
      let tasks = dlBatch.downloadTasks
      // We want to denote ALL language variants of a keyboard as part of the batch's metadata, even if we only download a single time.
      tasks.forEach { task in
        task.resources = keyboards
        task.resourceIDs = keyboards.map { $0.fullID }
      }
      
      // Perform common 'can download' check.  We need positive reachability and no prior download queue.
      let queueState = downloader.state
      if queueState != .clear {
        resourceDownloadFailed(for: keyboards, with: queueState.error!)
        return nil
      }
      
      downloader.queue(.simpleBatch(dlBatch))
      return dlBatch
    }
    return nil
  }
  
  private func buildKeyboardDownloadBatch(for keyboard: InstallableKeyboard,
                                          withFilename filename: String,
                                          asActivity activity: DownloadActivityType,
                                          withOptions options: Options,
                                          startBlock: (() -> Void)? = nil,
                                          completionBlock: CompletionHandler<InstallableKeyboard>? = nil) -> DownloadBatch<InstallableKeyboard.FullID>? {
    let keyboardURL = options.keyboardBaseURL.appendingPathComponent(filename)
    let fontURLs = Array(Set(keyboardFontURLs(forFont: keyboard.font, options: options) +
                             keyboardFontURLs(forFont: keyboard.oskFont, options: options)))

    do {
      try FileManager.default.createDirectory(at: Storage.active.resourceDir(for: keyboard)!,
                                              withIntermediateDirectories: true)
    } catch {
      log.error("Could not create dir for download: \(error)")
      return nil
    }

    var request = HTTPDownloadRequest(url: keyboardURL, userInfo: [:])
    request.destinationFile = Storage.active.cloudKeyboardURL(forID: keyboard.id).path
    request.tag = 0

    let keyboardTask = DownloadTask(do: request, for: [keyboard.fullID], resources: [keyboard])
    var batchTasks: [DownloadTask<InstallableKeyboard.FullID>] = [ keyboardTask ]
    
    for (i, url) in fontURLs.enumerated() {
      request = HTTPDownloadRequest(url: url, userInfo: [:])
      request.destinationFile = Storage.active.fontURL(forResource: keyboard, filename: url.lastPathComponent)!.path
      request.tag = i + 1
      
      let fontTask = DownloadTask<InstallableKeyboard.FullID>(do: request, for: nil)
      batchTasks.append(fontTask)
    }

    let batch = DownloadBatch(do: batchTasks, startBlock: startBlock, completionBlock: completionBlock)
    batchTasks.forEach { task in
      task.request.userInfo[Key.downloadBatch] = batch
      task.request.userInfo[Key.downloadTask] = task
    }
    
    return batch
  }

  /// Asynchronously fetches the .js file for the keyboard with given IDs.
  /// See `Notifications` for notification on success/failiure.
  /// - Parameters:
  ///   - isUpdate: Keep the keyboard files on failure
  ///   - fetchRepositoryIfNeeded: Fetch the list of keyboards from the API if necessary.
  public func downloadKeyboard(withID keyboardID: String,
                               languageID: String,
                               isUpdate: Bool,
                               fetchRepositoryIfNeeded: Bool = true,
                               completionBlock: CompletionHandler<InstallableKeyboard>? = nil) {
    guard let _ = Manager.shared.apiKeyboardRepository.keyboards,
      let options = Manager.shared.apiKeyboardRepository.options
    else {
      if fetchRepositoryIfNeeded {
        log.info("Fetching repository from API for keyboard download")
        Manager.shared.apiKeyboardRepository.fetch(completionHandler: fetchHandler(for: .keyboard) {
          self.downloadKeyboard(withID: keyboardID, languageID: languageID, isUpdate: isUpdate, fetchRepositoryIfNeeded: false, completionBlock: completionBlock)
        })
        return
      } else {
        let message = "Keyboard repository not yet fetched"
        let error = NSError(domain: "Keyman", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
        self.resourceDownloadFailed(for: [] as [InstallableKeyboard], with: error)
        return
      }
    }

    // Grab info for the relevant API version of the keyboard.
    guard let keyboard = getInstallableKeyboardMetadata(withID: keyboardID, languageID: languageID),
      let filename = Manager.shared.apiKeyboardRepository.keyboards?[keyboardID]?.filename
    else {
      return
    }

    let _ = downloadKeyboardCore(withMetadata: [keyboard],
                                 asActivity: isUpdate ? .update : .download,
                                 withFilename: filename,
                                 withOptions: options,
                                 completionBlock: completionBlock)
  }

  private func keyboardFontURLs(forFont font: Font?, options: Options) -> [URL] {
    guard let font = font else {
      return []
    }
    return font.source.filter({ $0.hasFontExtension })
      .map({ options.fontBaseURL.appendingPathComponent($0) })
  }
  
  /// - Returns: The current state for a keyboard
  public func stateForKeyboard(withID keyboardID: String) -> KeyboardState {
    // For this call, we don't actually need the language ID to be correct.
    let fullKeyboardID = FullKeyboardID(keyboardID: keyboardID, languageID: "")
    if downloader.containsResourceInQueue(matchingID: fullKeyboardID, requireLanguageMatch: false) {
      return .downloading
    }

    let userKeyboards = Storage.active.userDefaults.userKeyboards
    guard let userKeyboard = userKeyboards?.first(where: { $0.id == keyboardID }) else {
      return .needsDownload
    }

    // TODO:  convert to use of package-version API.
    // Check version
    if let repositoryVersionString = Manager.shared.apiKeyboardRepository.keyboards?[keyboardID]?.version {
      let downloadedVersion = Version(userKeyboard.version) ?? Version.fallback
      let repositoryVersion = Version(repositoryVersionString) ?? Version.fallback
      if downloadedVersion < repositoryVersion {
        return .needsUpdate
      }
    }
    return .upToDate
  }

  // MARK - Lexical models
  
  // Can be called by the keyboard downloader and utilized.
  
  /// Starts the process of fetching the package file of the lexical model for the given language ID
  ///   first it fetches the list of lexical models for the given language
  ///   then it takes the first of the list and download the KMP package file and asks the app to open it (like adhoc download)
  /// - Parameters:
  ///   - languageID: the bcp47 string of the desired language
  public func downloadLexicalModelsForLanguageIfExists(languageID: String) {
    // Note:  we aren't caching the result of this query in any way.
    // TODO:  There's no check to ensure we don't already have a model installed for the language.
    //        The original lacked this check, as well, and it's a bit of an edge case right now.
    Queries.LexicalModel.fetch(forLanguageCode: languageID) { result, error in
      if let error = error {
        log.info("Failed to fetch lexical model list for "+languageID+". error: "+error.localizedDescription)
        self.resourceDownloadFailed(for: [] as [InstallableLexicalModel], with: error)
        return
      }

      guard let result = result else {
        //TODO: put up an alert instead
        log.info("No lexical models available for language \(languageID) (nil)")
        return
      }

      if result.count == 0 {
        log.info("No lexical models available for language \(languageID) (empty)")
        // We automatically use the first model in the list.
      } else if let lmFullID = result[0].modelFor(languageID: languageID)?.fullID {
        log.info("Fetched lexical model list for "+languageID+".")
        let completionClosure = self.standardLexicalModelInstallCompletionBlock(forFullID: lmFullID)
        self.downloadPackage(forFullID: lmFullID, from: URL.init(string: result[0].packageFilename)!, completionBlock: completionClosure)
      }
    }
  }

  /// Asynchronously fetches the .js file for the lexical model with given IDs.
  /// See `Notifications` for notification on success/failiure.
  /// - Parameters:
  ///   - isUpdate: Keep the lexical model files on failure
  ///   - fetchRepositoryIfNeeded: Fetch the list of lexical models from the API if necessary.
  public func downloadLexicalModel(withID lexicalModelID: String,
                                   languageID: String,
                                   isUpdate: Bool,
                                   fetchRepositoryIfNeeded: Bool = true,
                                   completionBlock: CompletionHandler<InstallableLexicalModel>? = nil) {
    // Note:  in this case, someone knows the "full ID" of the model already, but NOT its location.
    //        For lexical models, we can use either the LexicalModel query or the PackageVersion query.
    //        For consistency with keyboard download behavior, we use the PackageVersion query here.

    let lmFullID = FullLexicalModelID(lexicalModelID: lexicalModelID, languageID: languageID)
    Queries.PackageVersion.fetch(for: [lmFullID], withSession: session) { result, error in
      guard let result = result, error == nil else {
        log.info("Error occurred requesting location for \(lmFullID.description)")
        self.resourceDownloadFailed(forFullID: lmFullID, with: error ?? .noData)
        completionBlock?(nil, error ?? .noData)
        return
      }

      guard case let .success(data) = result.entryFor(lmFullID) else {
        if case let .failure(errorEntry) = result.entryFor(lmFullID) {
          if let errorEntry = errorEntry {
            log.info("Query reported error: \(String(describing: errorEntry.error))")
          }
        }
        self.resourceDownloadFailed(forFullID: lmFullID, with: Queries.ResultError.unqueried)
        completionBlock?(nil, Queries.ResultError.unqueried)
        return
      }

      // Perform common 'can download' check.  We need positive reachability and no prior download queue.
      guard self.downloader.state == .clear else {
        let err = self.downloader.state.error ??
          NSError(domain: "Keyman", code: 0, userInfo: [NSLocalizedDescriptionKey: "Already busy downloading something"])
        self.resourceDownloadFailed(forFullID: lmFullID, with: err)
        completionBlock?(nil, err)
        return
      }

      let completionClosure: CompletionHandler<InstallableLexicalModel> = completionBlock ?? { package, error in
        // If the caller doesn't specify a completion block, this will carry out a default installation.
        if let package = package {
          try? ResourceFileManager.shared.install(resourceWithID: FullLexicalModelID(lexicalModelID: lexicalModelID, languageID: languageID), from: package)
        }
      }

      self.downloadPackage(forFullID: lmFullID,
                           from: URL.init(string: data.packageURL)!,
                           withNotifications: !isUpdate,
                           completionBlock: completionClosure)
    }
  }


  
  /// - Returns: The current state for a lexical model
  //TODO: rename KeyboardState to ResourceState? so it can be used with both keybaoards and lexical models without confusion
  public func stateForLexicalModel(withID lexicalModelID: String) -> KeyboardState {
    // For this call, we don't actually need the language ID to be correct.
    let fullLexicalModelID = FullLexicalModelID(lexicalModelID: lexicalModelID, languageID: "")
    if downloader.containsResourceInQueue(matchingID: fullLexicalModelID, requireLanguageMatch: false) {
      return .downloading
    }

    let userLexicalModels = Storage.active.userDefaults.userLexicalModels
    guard let userLexicalModel = userLexicalModels?.first(where: { $0.id == lexicalModelID }) else {
      return .needsDownload
    }

    // TODO:  Convert to use of package-version API.
    // Check version
    if let repositoryVersionString = Manager.shared.apiLexicalModelRepository.lexicalModels?[lexicalModelID]?.version {
      let downloadedVersion = Version(userLexicalModel.version) ?? Version.fallback
      let repositoryVersion = Version(repositoryVersionString) ?? Version.fallback
      if downloadedVersion < repositoryVersion {
        return .needsUpdate
      }
    }
    return .upToDate
  }

  /**
   * Downloads a package for the specified `LanguageResourceFullID` (`FullKeyboardID` / `FullLexicalModelID`)
   * and parses it automatically, given a pre-known URL.  The fully parsed package (`KeyboardKeymanPackage` /
   * `LexicalModelKeymanPackage`) or `Error` that results is available upon completion.
   *
   * Actual installation of the resource is left to calling code; consider use of `ResourceFileManager`'s `install` methods
   * with the returned package.
   *
   * `withNotifications` specifies whether or not any of KeymanEngine's `NotificationCenter` notifications should be generated.
   */
  public func downloadPackage<FullID: LanguageResourceFullID>(forFullID fullID: FullID,
                                                              from url: URL,
                                                              withNotifications: Bool = false,
                                                              completionBlock: @escaping CompletionHandler<FullID.Resource>)
  where FullID.Resource.Package: TypedKeymanPackage<FullID.Resource> {
    let batch = buildPackageBatch(forFullID: fullID, from: url, withNotifications: withNotifications, completionBlock: completionBlock)
    downloader.queue(.simpleBatch(batch))
  }

  // Facilitates re-use of the downloadPackage core for updates.
  // Also allows specifying LanguageResource instances for use in notifications.
  internal func buildPackageBatch<FullID: LanguageResourceFullID>(forFullID fullID: FullID,
                                                                  from url: URL,
                                                                  withNotifications: Bool = false,
                                                                  withResource resource: FullID.Resource? = nil,
                                                                  completionBlock: @escaping CompletionHandler<FullID.Resource>) -> DownloadBatch<FullID>
  where FullID.Resource.Package: TypedKeymanPackage<FullID.Resource> {
    var startClosure: (() -> Void)? = nil
    var completionClosure: CompletionHandler<FullID.Resource>? = completionBlock

    if withNotifications {
      let resources = resource != nil ? [resource!] : [] as [FullID.Resource]
      // We don't have the full metadata available, but we can at least signal which resource type this way.
      startClosure = resourceDownloadStartClosure(forFullID: fullID)
      completionClosure = resourceDownloadCompletionClosure(for: resources, handler: completionBlock)
    }

    // build batch for package
    return DownloadBatch(forPackageWithID: fullID, from: url, startBlock: startClosure, completionBlock: completionClosure)
  }
  
  // MARK: Update checks + management
  public var updatesAvailable: Bool {
    get {
      return getAvailableUpdates() != nil
    }
  }
  
  public func getAvailableUpdates() -> [AnyLanguageResource]? {
    // Relies upon KMManager's preload; this was the case before the rework.
    if Manager.shared.apiKeyboardRepository.languages == nil && Manager.shared.apiLexicalModelRepository.languages == nil {
      return nil
    }

    isDidUpdateCheck = true
    
    var updatables: [AnyLanguageResource] = []

    // Gets the list of current, local keyboards in need of an update.
    // Version matches the current version, not the updated version.
    let kbds = getUpdatableKeyboards()
    updatables.append(contentsOf: kbds)

    // Likewise for lexical models.
    let lexModels = getUpdatableLexicalModels()
    updatables.append(contentsOf: lexModels)
    
    if updatables.count > 0 {
      return updatables
    } else {
      return nil
    }
  }
  
  public func performUpdates(forResources resources: [AnyLanguageResource]) {
    // The plan is to create new notifications to handle batch updates here, rather than
    // require a UI to manage the update queue.
    var batches: [AnyDownloadBatch] = []
    
    resources.forEach { res in
      if let kbd = res as? InstallableKeyboard {
        if let filename = Manager.shared.apiKeyboardRepository.keyboards?[kbd.id]?.filename,
          let kbdUpdate = Manager.shared.apiKeyboardRepository.installableKeyboard(withID: kbd.id, languageID: kbd.languageID),
           let options = Manager.shared.apiKeyboardRepository.options {
          if let batch = self.buildKeyboardDownloadBatch(for: kbdUpdate, withFilename: filename, asActivity: .update, withOptions: options) {
            batches.append(batch)
          }
        }
      } else if let lex = res as? InstallableLexicalModel {
        if let filename = Manager.shared.apiLexicalModelRepository.lexicalModels?[lex.id]?.packageFilename,
           let path = URL.init(string: filename) {
          let batch = self.buildPackageBatch(forFullID: lex.fullID, from: path, withResource: lex) { package, error in
            if let package = package {
              try? ResourceFileManager.shared.install(resourceWithID: lex.fullID, from: package)
            }
            // else error:  already handled by wrapping closure set within buildPackageBatch.
          }
          batches.append(batch)
        }
      }
    }
    
    let batchUpdate = CompositeBatch(queue: batches.map { return DownloadNode.simpleBatch($0) },
                                     startBlock: resourceBatchUpdateStartClosure(for: resources),
                                     completionBlock: resourceBatchUpdateCompletionClosure(for: resources))
    downloader.queue(.compositeBatch(batchUpdate))
  }
  
  private func getUpdatableKeyboards() -> [InstallableKeyboard] {
    var updateQueue: [InstallableKeyboard] = []
    var kbIDs = Set<String>()
    
    // Build the keyboard update queue
    Storage.active.userDefaults.userKeyboards?.forEach { kb in
      let kbState = stateForKeyboard(withID: kb.id)
      if kbState == .needsUpdate {
        if(!kbIDs.contains(kb.id)) {
          kbIDs.insert(kb.id)
          updateQueue.append(kb)
        }
      }
    }
    
    return updateQueue
  }

  private func getUpdatableLexicalModels() -> [InstallableLexicalModel] {
    // Build the lexical model update queue
    var updateQueue: [InstallableLexicalModel] = []
    var lmIDs = Set<String>()
    
    Storage.active.userDefaults.userLexicalModels?.forEach { lm in
      let lmState = stateForLexicalModel(withID: lm.id)
      if lmState == .needsUpdate {
        if !lmIDs.contains(lm.id) {
          lmIDs.insert(lm.id)
          updateQueue.append(lm)
        }
      }
    }

    return updateQueue
  }

  @available(*, deprecated)
  public func installLexicalModelPackage(at packageURL: URL) -> InstallableLexicalModel? {
    do {
      if let package = try ResourceFileManager.shared.prepareKMPInstall(from: packageURL) as? LexicalModelKeymanPackage {
        try ResourceFileManager.shared.finalizePackageInstall(package, isCustom: false)
        // The reason we're deprecating it; only returns the first model, even if more language pairings are installed.
        return package.installables[0][0]
      } else {
        log.error("Specified package (at \(packageURL)) does not contain lexical models: \(KMPError.invalidPackage)")
        return nil
      }
    } catch {
      log.error("Error occurred while attempting to install package from \(packageURL): \(String(describing: error))")
      return nil
    }
  }

  // MARK - Completion handlers.

  internal func resourceDownloadStartClosure<Resource: LanguageResource>(for resources: [Resource]) -> (() -> Void) {
    return { self.resourceDownloadStarted(for: resources) }
  }

  internal func resourceDownloadStartClosure<FullID: LanguageResourceFullID>(forFullID fullID: FullID) -> (() -> Void) {
    return { self.resourceDownloadStarted(forFullID: fullID) }
  }

  // Only for use with individual downloads.  Updates should have different completion handling.
  internal func resourceDownloadCompletionClosure<Resource: LanguageResource>(for resources: [Resource], handler: CompletionHandler<Resource>?) -> CompletionHandler<Resource> {
    return { package, error in
      if let error = error {
        resources.forEach { resource in
          do {
            let resourcePath = Storage.active.resourceURL(for: resource)!
            if FileManager.default.fileExists(atPath: resourcePath.path) {
              try? FileManager.default.removeItem(at: resourcePath)
            }
          }
        }

        self.resourceDownloadFailed(for: resources, with: error)
      } else if let _ = package {
        // successful download
        // Problem:  this uses the lookup-version of the resources, which may not be perfect matches
        // for what lies within the newly-downloaded package.
        self.resourceDownloadCompleted(for: resources)
      }

      handler?(package, error)

      // After the custom handler operates, ensure that any changes it made are synchronized for use
      // with the app extension, too.
      let userDefaults = Storage.active.userDefaults
      userDefaults.set([Date()], forKey: Key.synchronizeSWKeyboard)
      userDefaults.synchronize()
    }
  }

  internal func resourceUpdateCompletionClosure<Resource: LanguageResource>(for resources: [Resource]) -> CompletionHandler<Resource> {
    // Updates should not generate notifications per resource.
    return { package, error in
      if let package = package {
        // Do not send notifications for individual resource updates.
        let resourceIDs: [Resource.FullID] = resources.map { $0.typedFullID }
        do {
          if let keyboards = resources as? [InstallableKeyboard], let package = package as? KeyboardKeymanPackage {
            // TEMP:  currently required because downloaded keyboards aren't actually in packages.
            keyboards.forEach { keyboard in
              if let updatedKbd = package.findResource(withID: keyboard.typedFullID) {
                Manager.shared.updateUserKeyboards(with: updatedKbd)

                if Manager.shared.currentKeyboard?.fullID == keyboard.fullID {
                  // Issue:  does not actually trigger a reload if the user isn't within the Settings view hierarchy
                  // Fixing this requires a refactor of `shouldReloadKeyboard`.
                  Manager.shared.shouldReloadKeyboard = true
                }
              }
            }
          } else if let _ = resources as? [InstallableLexicalModel] {
            try ResourceFileManager.shared.install(resourcesWithIDs: resourceIDs, from: package)
          }
        } catch {
          log.error("Error updating resources from package \(package.id)")
        }

        // After the custom handler operates, ensure that any changes it made are synchronized for use
        // with the app extension, too.
        let userDefaults = Storage.active.userDefaults
        userDefaults.set([Date()], forKey: Key.synchronizeSWKeyboard)
        userDefaults.synchronize()
      }
    }
  }

  internal func resourceBatchUpdateStartClosure(for resources: [AnyLanguageResource]) -> (() -> Void) {
    return {
      let notification = BatchUpdateStartedNotification(resources)
      NotificationCenter.default.post(name: Notifications.batchUpdateStarted,
                                      object: self,
                                      value: notification)
    }
  }

  internal func resourceBatchUpdateCompletionClosure(for resources: [AnyLanguageResource],
                                                     completionBlock: BatchCompletionHandler? = nil)
                                                     -> InternalBatchCompletionHandler {
    return { batch in
      var successes: [[AnyLanguageResource]] = []
      var failures: [[AnyLanguageResource]] = []
      var errors: [Error] = []

      // Remember, since this is for .composite batches, batch.tasks is of type [DownloadBatch].
      for (index, res) in batch.tasks.enumerated() {
        if batch.errors[index] == nil {
          let successSet: [AnyLanguageResource] = res.resourceIDs.compactMap { fullID in
            return resources.first(where: { resource in
              resource.fullID.matches(fullID)
            })
          }
          successes.append(successSet)
        } else {
          let failureSet: [AnyLanguageResource] = res.resourceIDs.compactMap { fullID in
            return resources.first(where: { resource in
              resource.fullID.matches(fullID)
            })
          }
          failures.append(failureSet)
          errors.append(batch.errors[index]!)
        }
      }

      let notification = BatchUpdateCompletedNotification(successes: successes, failures: failures, errors: errors)
      NotificationCenter.default.post(name: Notifications.batchUpdateCompleted,
                                      object: self,
                                      value: notification)
      completionBlock?()
    }
  }

  public func standardKeyboardInstallCompletionBlock(forFullID fullID: FullKeyboardID, withModel: Bool = true) -> CompletionHandler<InstallableKeyboard> {
    return { package, error in
      if let package = package {
        // The "keyboard package" is actually a cloud resource that was already directly installed.
        // So, we don't 'install it from the package'; we just note that it's already present.
        let fullID = FullKeyboardID(keyboardID: fullID.keyboardID, languageID: fullID.languageID)

        // Since we're installing from a cloud resource, the files are already appropriately placed.
        // We just need to actually add the resource.
        if let keyboard = package.findResource(withID: fullID) {
          ResourceFileManager.shared.addResource(keyboard)
          _ = Manager.shared.setKeyboard(keyboard)

          if withModel {
            self.downloadLexicalModelsForLanguageIfExists(languageID: fullID.languageID)
          }
        } else {
          log.error("Expected resource \(fullID.description) download failed; resource unexpectedly missing")
        }
      } else if let error = error {
        log.error("Installation failed: \(String(describing: error))")
      } else {
        log.error("Unknown error when attempting to install \(fullID.description))")
      }
    }
  }

  public func standardLexicalModelInstallCompletionBlock(forFullID fullID: FullLexicalModelID) -> CompletionHandler<InstallableLexicalModel> {
    return { package, error in
      if let package = package {
        do {
          // A raw port of the queue's old installation method for lexical models.
          try ResourceFileManager.shared.finalizePackageInstall(package, isCustom: false)
          log.info("successfully parsed the lexical model in: \(package.sourceFolder)")

          if let installedLexicalModel = package.findResource(withID: fullID) {
            _ = Manager.shared.registerLexicalModel(installedLexicalModel)
          }
        } catch {
          log.error("Error installing the lexical model: \(String(describing: error))")
        }
      } else if let error = error {
        log.error("Error downloading the lexical model \(String(describing: error))")
      } else {
        log.error("Unknown error when attempting to install \(fullID.description)")
      }
    }
  }

  // MARK - Notifications
  internal func resourceDownloadStarted<Resource: LanguageResource>(for resources: [Resource]) {
    if let keyboards = resources as? [InstallableKeyboard] {
      NotificationCenter.default.post(name: Notifications.keyboardDownloadStarted,
                                          object: self,
                                          value: keyboards)
    } else if let lexicalModels = resources as? [InstallableLexicalModel] {
      NotificationCenter.default.post(name: Notifications.lexicalModelDownloadStarted,
                                              object: self,
                                              value: lexicalModels)
    }
  }

  internal func resourceDownloadStarted<FullID: LanguageResourceFullID>(forFullID id: FullID) {
    // Note:  when all is said and done, we may want to rework notifications to report the FullID, not
    //        the full LanguageResource.
    if let _ = id as? FullKeyboardID {
      NotificationCenter.default.post(name: Notifications.keyboardDownloadStarted,
                                          object: self,
                                          value: [])
    } else if let _ = id as? FullLexicalModelID {
      NotificationCenter.default.post(name: Notifications.lexicalModelDownloadStarted,
                                              object: self,
                                              value: [])
    }
  }

  internal func resourceDownloadCompleted<Resource: LanguageResource>(for resources: [Resource]) {
    if let keyboards = resources as? [InstallableKeyboard] {
      let notification = KeyboardDownloadCompletedNotification(keyboards)
      NotificationCenter.default.post(name: Notifications.keyboardDownloadCompleted,
                                      object: self,
                                      value: notification)
    } else if let lexicalModels = resources as? [InstallableLexicalModel] {
      let notification = LexicalModelDownloadCompletedNotification(lexicalModels)
      NotificationCenter.default.post(name: Notifications.lexicalModelDownloadCompleted,
                                      object: self,
                                      value: notification)
    }
  }

  internal func resourceDownloadFailed<Resource: LanguageResource>(for resources: [Resource], with error: Error) {
    if let keyboards = resources as? [InstallableKeyboard] {
      let notification = KeyboardDownloadFailedNotification(keyboards: keyboards, error: error)
      NotificationCenter.default.post(name: Notifications.keyboardDownloadFailed,
                                      object: self,
                                      value: notification)
    } else if let lexicalModels = resources as? [InstallableLexicalModel] {
      // Sadly, this notification reports with a different format.
      let languageID = lexicalModels.count > 0 ? lexicalModels[0].languageID : ""
      let notification = LexicalModelDownloadFailedNotification(lmOrLanguageID: languageID, error: error)
      NotificationCenter.default.post(name: Notifications.lexicalModelDownloadFailed,
                                      object: self,
                                      value: notification)
    }
  }

  internal func resourceDownloadFailed<FullID: LanguageResourceFullID>(forFullID fullID: FullID, with error: Error) {
    if let _ = fullID as? FullKeyboardID {
      let notification = KeyboardDownloadFailedNotification(keyboards: [], error: error)
      NotificationCenter.default.post(name: Notifications.keyboardDownloadFailed,
                                      object: self,
                                      value: notification)
    } else if let _ = fullID as? FullLexicalModelID {
      let notification = LexicalModelDownloadFailedNotification(lmOrLanguageID: fullID.languageID, error: error)
      NotificationCenter.default.post(name: Notifications.lexicalModelDownloadFailed,
                                      object: self,
                                      value: notification)
    }
  }
}
