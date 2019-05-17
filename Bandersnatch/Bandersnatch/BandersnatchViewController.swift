//
//  BandersnatchViewController.swift
//
//  Created by Mo DeJong on 5/7/19.
//  Copyright © 2019 Mo DeJong. All rights reserved.
//

import UIKit
import AlphaOverVideo

class BandersnatchViewController: UIViewController {
  
  @IBOutlet weak var mtkView: AOVMTKView!
  var player: AOVPlayer?
  
  // UI elements for choice of cereal scene
  
  @IBOutlet weak var buttonContainer: UIView!
  @IBOutlet weak var leftButton: UIButton!
  @IBOutlet weak var rightButton: UIButton!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    assert(self.mtkView != nil)
    assert(self.buttonContainer != nil)
    
    print("BandersnatchViewController.viewDidLoad")
    
    configurePlayerView()
    
    self.buttonContainer.alpha = 0.0
    self.buttonContainer.backgroundColor = UIColor.clear
  }
  
  func configurePlayerView() {
    mtkView.device = MTLCreateSystemDefaultDevice()
    
    if (mtkView.device == nil)
    {
      NSLog("Metal is not supported on this device");
      return;
    }
    
    let url1 = AOVPlayer.url(fromAsset:"Intro.m4v")
    assert(url1 != nil)
    let url2 = AOVPlayer.url(fromAsset:"ClipAChoiceFrostiesOrPuffs.m4v")
    assert(url2 != nil)
    // Show
    
    // Configure for 2 opaque clips
    let clips = [ url1 as Any, url2 as Any ]
    
    let player = AOVPlayer.init(clips:clips)
    self.player = player
    
    assert(player?.hasAlphaChannel == false)
    
    // Defaults to sRGB, so set BT.709 flag to indicate video encoding
    player?.decodeGamma = AOVGammaApple;
    
    // Transition to choose vc after first 2 clips have finished playing
    
    player?.videoPlaybackFinishedBlock = {
      self.launchChooseCerealVideo()
    }
    
    let worked = mtkView.attach(player)
    if (worked == false)
    {
      NSLog("attach failed for AOVMTKView");
      return;
    }
  }
  
  // Transition into choice of cereal scene

  func launchChooseCerealVideo() {
    print("launchChooseCerealVideo")
    
    startChoiceVideo()
    animateShowButtons()
  }
  
  // This method is invoked to kick off a looping clip that zooms in on the
  // title character while a cereal selection is being made.
  
  func startChoiceVideo() {
    let url = AOVPlayer.url(fromAsset:"ClipBChoiceFrostiesOrPuffs.m4v")
    assert(url != nil)
    
    mtkView.detach(self.player)
    
    let player = AOVPlayer.init(loopedClip:url)
    self.player = player
    
    assert(player?.hasAlphaChannel == false)
    
    // Defaults to sRGB, so set BT.709 flag to indicate video encoding
    player?.decodeGamma = AOVGammaApple;
    
    // Transition to choose vc after first 2 clips have finished playing
    
    let worked = mtkView.attach(player)
    if (worked == false)
    {
      NSLog("attach failed for AOVMTKView");
      return;
    }
  }
  
  func animateShowButtons() {
    print("animateShowButtons")
    
    self.buttonContainer.alpha = 0.0
    
    // Change size of view to 85% of original height with same origin and show buttons
    // with a fade in effect
    
    UIView.animate(withDuration: 3.0, delay: 0.0, options: .curveEaseIn, animations: {
      let mainView = self.view!
      let mtkView = self.mtkView!
      
      let rect = mtkView.frame
      //print("initial mtkView frame dimensions \(rect.origin.x) \(rect.origin.y) : \(rect.size.width) x \(rect.size.height)")
      
      let viewHeight = mainView.frame.size.height
      let buttonFrameHeight = self.buttonContainer.frame.size.height
      
      let expectedWidth = rect.size.width
      let expectedHeight = viewHeight - buttonFrameHeight
      
      let resizedRect = CGRect(
        origin: CGPoint(x: rect.origin.x, y: rect.origin.y),
        size: CGSize(width: expectedWidth, height: expectedHeight)
      )
      
      mtkView.frame = resizedRect
      
      //print("final mtkView frame dimensions \(resizedRect.origin.x) \(resizedRect.origin.y) : \(resizedRect.size.width) x \(resizedRect.size.height)")
      
      self.buttonContainer.alpha = 1.0
    }, completion: { finished in
      print("Animation Completed!")
      
      self.leftButton.isEnabled = true
      self.rightButton.isEnabled = true
    })
  }
  
  func animateHideButtons() {
    print("animateHideButtons")
    
    self.buttonContainer.alpha = 1.0
    
    UIView.animate(withDuration: 3.0, delay: 0.0, options: .curveEaseOut, animations: {
      let mtkView = self.mtkView!
      
      let rect = mtkView.frame
      
      let expectedWidth = rect.size.width
      let expectedHeight = self.view.frame.size.height
      
      let resizedRect = CGRect(
        origin: CGPoint(x: rect.origin.x, y: rect.origin.y),
        size: CGSize(width: expectedWidth, height: expectedHeight)
      )
      
      mtkView.frame = resizedRect
      
      self.buttonContainer.alpha = 0.0
    }, completion: { finished in
      print("Animation Completed!")
      self.launchOutroVideo()
    })
  }
  
  @IBAction func leftButton(sender: UIButton) {
    print("leftButton")
    self.leftButton.isEnabled = false
    self.rightButton.isEnabled = false
    self.animateHideButtons()
  }
  
  @IBAction func rightButton(sender: UIButton) {
    print("rightButton")
    self.leftButton.isEnabled = false
    self.rightButton.isEnabled = false
    self.animateHideButtons()
  }
  
  func launchOutroVideo() {
    print("launchOutroVideo")
    self.performSegue(withIdentifier:"launchOutroVideo", sender:nil)
  }
}

