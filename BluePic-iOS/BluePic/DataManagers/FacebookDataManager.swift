/**
 * Copyright IBM Corporation 2015
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/


import UIKit


/// Manages all facebook authentication state and calls
class FacebookDataManager: NSObject {
    
    /// Shared instance of data manager
    static let SharedInstance: FacebookDataManager = {
        
        var manager = FacebookDataManager()
        
        
        return manager
        
    }()
    

    private override init() {} //This prevents others from using the default '()' initializer for this class.

    /// Facebook app ID
    var fbAppID: String?
    
    /// Display name for the app on Facebook
    var fbAppDisplayName: String?
    
    /// Display name for user on Facebook
    var fbUserDisplayName: String?
    
    /// Unique user ID given from Facebook API
    var fbUniqueUserID: String?
    
    /// Bool if user is authenticated with facebook
    var isLoggedIn = false
    
    /// Prefix for url needed to get user profile picture given their unique id (id goes after this)
    let facebookProfilePictureURLPrefix = "http://graph.facebook.com/"
    
    /// Postfix for url needed to get user profile picture given their unique id (id goes before this)
    let facebookProfilePictureURLPostfix = "/picture?type=large"
    
    /**
     Custom enum for whether facebook authentication was successful or not
     
     - Success: successful
     - Failure: failure to connect
     */
    enum NetworkRequest {
        case Success
        case Failure
    }
    
    
    /**
     Method to auth user using Facebook SDK
     
     - parameter callback: Success or Failure
     */
    func authenticateUser(callback : ((networkRequest : NetworkRequest) -> ())){
        if (self.checkIMFClient() && self.checkAuthenticationConfig()) {
            self.getAuthToken(callback)
        }
        else{
            callback(networkRequest: NetworkRequest.Failure)
        }
        
    }
    
    
    /**
     Method to get authentication token from Facebook SDK
     
     - parameter callback: Success or Failure
     */
    func getAuthToken(callback : ((networkRequest: NetworkRequest) -> ())) {
       let authManager = IMFAuthorizationManager.sharedInstance()
        authManager.obtainAuthorizationHeaderWithCompletionHandler( {(response: IMFResponse?, error: NSError?) in
            let errorMsg = NSMutableString()
            
            //error
            if let errorObject = error {
                callback(networkRequest: NetworkRequest.Failure)
                errorMsg.appendString("Error obtaining Authentication Header.\nCheck Bundle Identifier and Bundle version string\n\n")
                if let responseObject = response {
                    if let responseString = responseObject.responseText {
                        errorMsg.appendString(responseString)
                    }
                }
                let userInfo = errorObject.userInfo
                errorMsg.appendString(userInfo.description)
            }
                
                //no error
            else {
                if let identity = authManager.userIdentity {
                    if let userID = identity["id"] as? NSString {
                        if let userName = identity["displayName"] as? NSString {
                        
                            //save username and id to shared instance of this class
                            self.fbUniqueUserID = userID as String
                            self.fbUserDisplayName = userName as String
                        
                            //set user logged in
                            self.isLoggedIn = true
                            
                            //save user id and name for future app launches
                            NSUserDefaults.standardUserDefaults().setObject(userID, forKey: "user_id")
                            NSUserDefaults.standardUserDefaults().setObject(userName, forKey: "user_name")
                            NSUserDefaults.standardUserDefaults().synchronize()
                            
                        
                            print("Got facebook auth token for user \(userName) with id \(userID)")
                            
                            self.checkIfUserExistsOnCloudantAndPushIfNeeded()
                            
                            callback(networkRequest: NetworkRequest.Success)
                        }
                    }
                    else {
                        print("Valid Authentication Header and userIdentity, but id not found")
                        callback(networkRequest: NetworkRequest.Failure)
                    }
                    
                }
                else {
                    print("Valid Authentication Header, but userIdentity not found. You have to configure one of the methods available in Advanced Mobile Service on Bluemix, such as Facebook")
                    callback(networkRequest: NetworkRequest.Failure)
                }
                
                
            }
            
            })
        
    }
    
    
    /**
     Method to check to make sure IMFClient is valid (route and GUID)
     
     - returns: true or false if valid or not
     */
    func checkIMFClient() -> Bool {
        let imfClient = IMFClient.sharedInstance()
        let route = imfClient.backendRoute
        let guid = imfClient.backendGUID
        
        if (route == nil || route.characters.count == 0) {
            print ("Invalid Route.\n Check applicationRoute in appdelegate")
            return false
        }
        
        if (guid == nil || guid.characters.count == 0) {
            print ("Invalid GUID.\n Check applicationId in appdelegate")
            return false
        }
        return true
        
    }
    
    
    
    /**
     Method to check if Facebook is configured
     
     - returns: true if configured, false if not
     */
    func checkAuthenticationConfig() -> Bool {
        if (self.isFacebookConfigured()) {
            return true
        } else {
            print("Authentication is not configured in Info.plist. You have to configure Info.plist with the same Authentication method configured on Bluemix such as Facebook")
            return false
        }
        
        
    }
    
    
    /**
     Method to check if Facebook SDK is setup on native iOS side and all required keys have been added to plist
     
     - returns: true if configured, false if not
     */
    func isFacebookConfigured() -> Bool {
        let facebookAppID = NSBundle.mainBundle().objectForInfoDictionaryKey("FacebookAppID") as? NSString
        let facebookDisplayName = NSBundle.mainBundle().objectForInfoDictionaryKey("FacebookDisplayName") as? NSString
        let urlTypes = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleURLTypes") as? NSArray
        
        let urlTypes0 = urlTypes!.firstObject as? NSDictionary
        let urlSchemes = urlTypes0!["CFBundleURLSchemes"] as? NSArray
        let facebookURLScheme = urlSchemes!.firstObject as? NSString
        
        if (facebookAppID == nil || facebookAppID!.isEqualToString("") || facebookAppID == "123456789") {
            return false
        }
        if (facebookDisplayName == nil || facebookDisplayName!.isEqualToString("")) {
            return false
        }
        
        if (facebookURLScheme == nil || facebookURLScheme!.isEqualToString("") || facebookURLScheme!.isEqualToString("fb123456789") || !(facebookURLScheme!.hasPrefix("fb"))) {
            return false
        }
        
        //success if made it past this point
        
        
        
        //save app ID and app display name to this class
        self.fbAppID = facebookAppID! as String
        self.fbAppDisplayName = facebookDisplayName! as String
        

        print("Facebook Auth configured, getting ready to show native FB Login:\nFacebookAppID \(facebookAppID!)\nFacebookDisplayName \(facebookDisplayName!)\nFacebookURLScheme \(facebookURLScheme!)")
        return true;
    }
    
    
    
    /**
     Method will try to first authenticate with Object storage. If successful, wil try to show login screen if not authenticated with Facebook. If failure, will retry authentication with object storage
     
     - parameter presentingVC: tab bar VC to show error alert if it occurs
     */
    func tryToShowLoginScreen() {
        //authenticate with object storage every time opening app, try to show facebook login once completed
        if (!ObjectStorageDataManager.SharedInstance.objectStorageClient.isAuthenticated()) { //try to authenticate if not authenticated
            print("Attempting to authenticate with Object storage...")
            ObjectStorageDataManager.SharedInstance.objectStorageClient.authenticate({() in
                    print("success authenticating with object storage!")
                    self.showLoginIfUserNotAuthenticated()
                }, onFailure: {(error) in
                    print("error authenticating with object storage: \(error)")
                    DataManagerCalbackCoordinator.SharedInstance.sendNotification(DataManagerNotification.ObjectStorageAuthError)
            })
        }
        else { //if already authenticated with object storage, just try to show facebook login
            print("Object storage already authenticated somehow!")
            self.showLoginIfUserNotAuthenticated()
            
        }
   
    }
    
    
    
    /**
     Method will pull down latest cloudant data, and try to show login screen if user is not authenticated nor has pressed "sign in later" button
     
     - parameter presentingVC: tab bar VC to present login VC on
     */
    func showLoginIfUserNotAuthenticated() {
        //start pulling from cloudant sync (will automatically hide loading when successful)
        print("Pulling latest cloudant data...")
        self.pullLatestCloudantData()
        
        //check if user is already authenticated previously
        print("Checking if user is authenticated with facebook...")
        if let userID = NSUserDefaults.standardUserDefaults().objectForKey("user_id") as? String {
            if let userName = NSUserDefaults.standardUserDefaults().objectForKey("user_name") as? String {
                self.fbUserDisplayName = userName
                self.fbUniqueUserID = userID
                DataManagerCalbackCoordinator.SharedInstance.sendNotification(DataManagerNotification.GotPastLoginCheck)
                print("User already logged into Facebook. Welcome back, user \(userID)!")
            }
        }
        else { //user not authenticated
            
            //show login if user hasn't pressed "sign in later" (first time logging in)
            if !NSUserDefaults.standardUserDefaults().boolForKey("hasPressedLater") {
                DataManagerCalbackCoordinator.SharedInstance.sendNotification(DataManagerNotification.UserNotAuthenticated)
                
            } else { //user pressed "sign in later"
                DataManagerCalbackCoordinator.SharedInstance.sendNotification(DataManagerNotification.GotPastLoginCheck)
                
                print("user pressed sign in later button")
                
            }
        }
        
    }
    

    
    
    /**
     Method to start pulling the latest cloudant data
     */
    func pullLatestCloudantData() {
        
        //First do a pull to make sure datastore is up to date
        do {
            try CloudantSyncDataManager.SharedInstance!.pullFromRemoteDatabase()
        } catch {
            print("pullLatestCloudantData ERROR: \(error)")
            DataManagerCalbackCoordinator.SharedInstance.sendNotification(DataManagerNotification.CloudantPullDataFailure)
        }
        
        
    }
    
    
    /**
     Query CloudantSync to see if id exists, and push to database if needed. Will wait until pull replicator is finished to execute
     */
    func checkIfUserExistsOnCloudantAndPushIfNeeded() {
        
        //Check if doc with fb id exists
        if(!CloudantSyncDataManager.SharedInstance!.doesExist(self.fbUniqueUserID!))
        {
            do {
                //Create profile document locally
                try CloudantSyncDataManager.SharedInstance!.createProfileDoc(self.fbUniqueUserID!, name: self.fbUserDisplayName!)
            } catch {
                print("checkIfUserExistsOnCloudantAndPushIfNeeded ERROR: \(error)")
                DataManagerCalbackCoordinator.SharedInstance.sendNotification(DataManagerNotification.CloudantCreateProfileFailure)
            }
            
            do {
                //Push new profile document to remote database
                try CloudantSyncDataManager.SharedInstance!.pushToRemoteDatabase()
            } catch {
                print("checkIfUserExistsOnCloudantAndPushIfNeeded ERROR: \(error)")
                DataManagerCalbackCoordinator.SharedInstance.sendNotification(DataManagerNotification.CloudantPushDataFailure)
            }
            
            
        }
        
    }
    
    
    /**
     Method to return a url for the user's profile picture
     
     - returns: string representing the image url
     */
    func getUserFacebookProfilePictureURL() -> String {
        if let facebookID = fbUniqueUserID {
            
            let profilePictureURL = facebookProfilePictureURLPrefix + facebookID + facebookProfilePictureURLPostfix
            
            return profilePictureURL
        }
        else{
            return ""
        }
    }
    
    
    
}
