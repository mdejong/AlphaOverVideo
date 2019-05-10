//
//  ChooseViewController.swift
//  Bandersnatch
//
//  Created by Mo DeJong on 5/8/19.
//  Copyright © 2019 HelpURock. All rights reserved.
//

import Foundation

import UIKit
import AlphaOverVideo

class ChooseViewController: UIViewController {
  
  @IBOutlet weak var mtkView: AOVMTKView!
  var player: AOVPlayer?

  @IBOutlet weak var buttonContainer: UIView!
  @IBOutlet weak var leftButton: UIButton!
  @IBOutlet weak var rightButton: UIButton!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    assert(self.mtkView != nil)
    assert(self.buttonContainer != nil)
    
    print("ChooseViewController.viewDidLoad")
    
    mtkView.device = MTLCreateSystemDefaultDevice()
    
    if (mtkView.device == nil)
    {
      NSLog("Metal is not supported on this device");
      return;
    }
    
    let url = AOVPlayer.url(fromAsset:"ClipBChoiceFrostiesOrPuffs.m4v")
    assert(url != nil)
    
    let player = AOVPlayer.init(loopedClip:url)
    self.player = player
    
    // Defaults to sRGB, so set BT.709 flag to indicate video encoding
    player?.decodeGamma = MetalBT709GammaApple;
    
    let worked = mtkView.attach(player)
    if (worked == false)
    {
      NSLog("attach failed for AOVMTKView");
      return;
    }
    
    self.buttonContainer.alpha = 0.0
    self.buttonContainer.backgroundColor = UIColor.clear
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    let delaySeconds = 0.5
    DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
      self.animateShowButtons()
    }
  }

  func animateShowButtons() {
    print("animateShowButtons")
    
    self.buttonContainer.alpha = 0.0
    
    // Change size of view to 85% of original height with same origin and show buttons
    // with a fade in effect
    
    UIView.animate(withDuration: 3.0, delay: 0.0, options: .curveEaseIn, animations: {
      let view = self.mtkView!
      
      let rect = view.frame

      let viewHeight = self.view.frame.size.height
      let buttonFrameHeight = self.buttonContainer.frame.size.height
      let expectedHeight = viewHeight - buttonFrameHeight

      let resizedRect = CGRect(
        origin: CGPoint(x: rect.origin.x, y: rect.origin.y),
        size: CGSize(width:rect.size.width, height: expectedHeight)
      )
      
      view.frame = resizedRect
      
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
      let view = self.mtkView!
      
      let rect = view.frame
      
      let viewHeight = self.view.frame.size.height
      
      let resizedRect = CGRect(
        origin: CGPoint(x: rect.origin.x, y: rect.origin.y),
        size: CGSize(width:rect.size.width, height: viewHeight)
      )
      
      view.frame = resizedRect
      
      self.buttonContainer.alpha = 0.0
    }, completion: { finished in
      print("Animation Completed!")
    })
  }
  
  @IBAction func leftButton(sender: UIButton) {
    print("leftButton")
    self.leftButton.isEnabled = false
    self.rightButton.isEnabled = false
    self.animateHideButtons()
    self.launchOutroVideo()
  }
  
  @IBAction func rightButton(sender: UIButton) {
    print("rightButton")
    self.leftButton.isEnabled = false
    self.rightButton.isEnabled = false
    self.animateHideButtons()
    self.launchOutroVideo()
  }

  func launchOutroVideo() {
    print("launchOutroVideo")
    self.performSegue(withIdentifier:"launchOutroVideo", sender:nil)
  }
  
}
