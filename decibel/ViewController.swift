//
//  ViewController.swift
//  decibel
//
//  Created by Tomas Radvansky on 03/01/2016.
//  Copyright © 2016 Tomas Radvansky. All rights reserved.
//

import UIKit
import AVFoundation
import GaugeKit
import CircleSlider
import AudioToolbox
import GoogleMobileAds

extension String {
    var NS: NSString { return (self as NSString) }
}

class ViewController: UIViewController,AVAudioRecorderDelegate,AVAudioPlayerDelegate,GADBannerViewDelegate {
    
    @IBOutlet weak var gaugeView: Gauge!
    @IBOutlet weak var dbText: UILabel!
    @IBOutlet weak var circleParentView: UIView!
    @IBOutlet weak var bannerView: GADBannerView!
    @IBOutlet weak var limitDbText: UILabel!
    
    let audioSession = AVAudioSession.sharedInstance()
    var audioRecorder:AVAudioRecorder?
    var audioPlayer:AVAudioPlayer?
    var meteringTimer:NSTimer?
    var circleSlider:CircleSlider!
    let defaults:NSUserDefaults = NSUserDefaults.standardUserDefaults()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ViewController.StartMonitoring), name: UIApplicationWillEnterForegroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ViewController.StopMonitoring), name: UIApplicationWillResignActiveNotification, object: nil)
        bannerView.delegate = self
        bannerView.adUnitID = "ca-app-pub-9829129965826807/1695243377"
        bannerView.rootViewController = self
        let request = GADRequest()
        //request.testDevices = ["3eb5de996611a94246463efcdb78ff0a"]
        bannerView.loadRequest(request)
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        if circleSlider == nil
        {
            circleSlider = CircleSlider(frame: self.circleParentView.frame, options: [.BarColor(UIColor(red: 198/255, green: 244/255, blue: 23/255, alpha: 0.2)),
                .ThumbColor(UIColor(red: 141/255, green: 185/255, blue: 204/255, alpha: 1)),
                .TrackingColor(UIColor(red: 78/255, green: 136/255, blue: 185/255, alpha: 1)),
                .BarWidth(20),
                .StartAngle(-90),
                .MaxValue(100),
                .MinValue(-100)])
            
            if let dbValue:Int = defaults.integerForKey("DBInt")
            {
                if dbValue == 0
                {
                    defaults.setInteger(100, forKey: "DBInt")
                    defaults.synchronize()
                    self.circleSlider.value = 100
                }
                else
                {
                    self.circleSlider.value = Float(dbValue)
                }
            }
            else
            {
                defaults.setFloat(100, forKey: "DBInt")
                defaults.synchronize()
                self.circleSlider.value = 100
            }
            
            self.circleSlider.addTarget(self, action: #selector(ViewController.CircleSliderValueChanged), forControlEvents: .ValueChanged)
            self.circleSlider.addTarget(self, action: #selector(ViewController.CircleSliderTouchDown(_:)), forControlEvents: .TouchDown)
            self.circleSlider.addTarget(self, action: #selector(ViewController.CircleSliderTouchUp(_:)), forControlEvents: .TouchUpInside)
            
            self.circleParentView.addSubview(circleSlider)
        }
        
        loadUI()
        self.StartMonitoring()
    }
    
    func CircleSliderValueChanged(sender:CircleSlider!)
    {
        defaults.setFloat(circleSlider.value, forKey: "DBInt")
        defaults.synchronize()
        loadUI()
    }
    
    func CircleSliderTouchDown(sender:CircleSlider!)
    {
        self.audioRecorder?.stop()
    }
    
    func CircleSliderTouchUp(sender:CircleSlider!)
    {
        self.audioRecorder?.record()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        StopMonitoring()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func loadUI()
    {
        if let dbValue:Int = defaults.integerForKey("DBInt")
        {
            limitDbText.text = "(\(dbValue)dB)"
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    //MARK:- States
    func StartMonitoring()
    {
        print("StartMonitoring")
        if checkPermissions()
        {
            //Setup Audio
            let audioFilename = getDocumentsDirectory().NS.stringByAppendingPathComponent("recording.caf")
            let audioURL = NSURL(fileURLWithPath: audioFilename)
            
            let settings = [
                AVFormatIDKey: Int(kAudioFormatAppleIMA4),
                AVSampleRateKey: 44100.0,
                AVLinearPCMBitDepthKey:16 as NSNumber,
                AVNumberOfChannelsKey: 1 as NSNumber,
                AVLinearPCMIsBigEndianKey:0 as NSNumber,
                AVLinearPCMIsFloatKey:0 as NSNumber
            ]
            
            do {
                try audioSession.setActive(true)
                try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, withOptions: .MixWithOthers)
                
                if let soundURL = NSBundle.mainBundle().URLForResource("buzzer", withExtension: "caf") {
                    self.audioPlayer = try AVAudioPlayer(contentsOfURL: soundURL)
                    self.audioPlayer?.delegate = self
                    self.audioPlayer?.prepareToPlay()
                }
                
                self.audioRecorder = try AVAudioRecorder(URL: audioURL, settings: settings)
                self.audioRecorder?.delegate = self
                self.audioRecorder?.prepareToRecord()
                self.audioRecorder?.meteringEnabled = true
                self.audioRecorder?.record()
                dispatch_async(dispatch_get_main_queue(), {
                      self.meteringTimer = NSTimer.scheduledTimerWithTimeInterval(0.10, target: self, selector: #selector(ViewController.UpdateMeter), userInfo: nil, repeats: true)
                })
                   
                
            } catch let error as NSError {
                print(error.description)
            }
        }
    }
    
    func checkPermissions()->Bool
    {
        let microPhoneStatus = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeAudio)
        switch microPhoneStatus {
        case .Authorized:
            print("checkPermissions - true")
            return true
        // Microphone disabled in settings
        case .NotDetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { (answer:Bool) in
                if (answer == true)
                {
                    self.StartMonitoring()
                }
                else
                {
                    self.checkPermissions()
                }
            }
            print("checkPermissions - false")
            return false
        case .Restricted, .Denied:
            print("microPhoneStatus - .NotDetermined, .Restricted, .Denied")
            // Didn't request access yet
            let alertVC:UIAlertController = UIAlertController(title: "Microphone Permission", message: "Please allow access microphone in order to use this applications", preferredStyle: .Alert)
            alertVC.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: { (action:UIAlertAction) in
                //
            }))
            alertVC.addAction(UIAlertAction(title: "Settings", style: .Default, handler: { (action:UIAlertAction) in
                dispatch_async(dispatch_get_main_queue(), {
                    UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
                })
            }))
            self.presentViewController(alertVC, animated: true, completion: nil)
            print("checkPermissions - false")
            return false
        }
    }
    
    func audioPlayerDidFinishPlaying(player: AVAudioPlayer, successfully flag: Bool) {
        self.audioRecorder?.record()
    }
    
    func StopMonitoring()
    {
        print("Stop Monitoring")
        meteringTimer?.invalidate()
        meteringTimer = nil
        do {
            audioRecorder?.stop()
            try audioSession.setActive(false)
        } catch {
            
        }
    }
    var timer:NSTimer?
    
    //MARK:-Audio Metering
    func UpdateMeter()
    {
        if self.audioRecorder?.recording == true
        {
            self.audioRecorder!.updateMeters()
            let power = self.audioRecorder!.averagePowerForChannel(0)
            //On db scale when -100 is max Loud and 100 is max silent
            //All together 200 points
            // 200 * ratio -> 200 * 0.5 -> 100
            //On Apple scale -160 max silent and 0 is max loud
            //Normalized power transpose Apple scale to 0...1 (max value)
            //0.6 empirial value corresponding to -90db (-16 of Apple power) but it can be adjusted
            let nPower = self.normalizedPower(power)
            self.gaugeView.rate = CGFloat(nPower * 100)
            self.dbText.text = "\(Int(nPower*200.0)-100)dB"
            
            if let dbValue:Int = defaults.integerForKey("DBInt")
            {
                if (Int(nPower*200.0)-100) >= dbValue
                {
                    if timer == nil
                    {
                        self.audioRecorder?.stop()
                        timer=NSTimer.scheduledTimerWithTimeInterval(3.0, target: self, selector: #selector(ViewController.SoundFunction), userInfo: nil, repeats: false)
                    }
                }
            }
        }
    }
    
    func SoundFunction()
    {
        // to play sound
        self.audioPlayer?.play()
        timer?.invalidate()
        timer = nil
    }
    
    //MARK:- Helper
    func getDocumentsDirectory() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    
    //Values from 0 -> 1
    func normalizedPower(decibels:Float)->Float
    {
        if (decibels < -60)
        {
            return 0.0
        }
        else
        {
            let root:Float = 2.0
            let minAmp:Float = powf(10.0, 0.05 * -60.0)
            let inverseAmpRange:Float = 1.0 / (1.0 - minAmp)
            let amp:Float = powf(10.0, 0.05 * decibels)
            let adjAmp:Float = (amp - minAmp) * inverseAmpRange
            
            return powf(adjAmp, 1.0 / root);
        }
    }
    
    func adViewDidReceiveAd(bannerView: GADBannerView!) {
        print("adViewDidReceiveAd")
        bannerView.hidden = false
    }
    
    func adView(bannerView: GADBannerView!, didFailToReceiveAdWithError error: GADRequestError!) {
        bannerView.hidden = true
        print(error.description)
    }
    
    
}

