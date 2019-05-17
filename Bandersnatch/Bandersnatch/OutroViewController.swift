//
//  OutroViewController.swift
//
//  Created by Mo DeJong on 5/7/19.
//  Copyright © 2019 Mo DeJong. All rights reserved.
//

import UIKit
import AlphaOverVideo

class OutroViewController: UIViewController {
  
  @IBOutlet weak var mtkView: AOVMTKView!
  var player: AOVPlayer?
  
  @IBOutlet weak var textOverlay: UITextView!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    assert(mtkView != nil)
    assert(textOverlay != nil)

    print("OutroViewController.viewDidLoad")
    
    mtkView.device = MTLCreateSystemDefaultDevice()
    
    if (mtkView.device == nil)
    {
      NSLog("Metal is not supported on this device");
      return;
    }

    let url = AOVPlayer.url(fromAsset:"ClipYouBuryDad.m4v")
    assert(url != nil)
    
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
    
    setDadText1()
  }

  func setDadText1() {
    self.textOverlay.text = "A few days later ..."
  }
  
  func setDadText2() {
    self.textOverlay.text = "A few days later ...\nYou killed your Dad!"
  }
  
  func setDadText3() {
    self.textOverlay.text = "A few days later ...\nYou killed your Dad!\nEnjoy prision, crazy pants."
  }

  // Fade in animation
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    
    self.view.alpha = 0.0
    let fadeInTime = 2.0
    
    UIView.animate(withDuration: fadeInTime, delay: 0.0, options: .curveEaseIn, animations: {
      self.view.alpha = 1.0
    }, completion: { finished in
      print("Animation Completed!")
      
      let delaySeconds1 = 3.0
      DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds1) {
        self.setDadText2()
      }
      
      let delaySeconds2 = 6.0
      DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds2) {
        self.setDadText3()
      }
    })

  }
}

