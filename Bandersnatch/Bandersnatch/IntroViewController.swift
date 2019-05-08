//
//  IntroViewController.swift
//
//  Created by Mo DeJong on 5/7/19.
//  Copyright © 2019 HelpURock. All rights reserved.
//

import UIKit
import AlphaOverVideo

class IntroViewController: UIViewController {
  
  @IBOutlet weak var mtkView: AOVMTKView!
  var player: AOVPlayer?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    assert(mtkView != nil)

    print("IntroViewController.viewDidLoad")
    
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
    let clips = [ url1, url2 ] as [Any]
    
    let player = AOVPlayer.init(loopedClips:clips)
    self.player = player
    
    // Defaults to sRGB, so set BT.709 flag to indicate video encoding
    player?.decodeGamma = MetalBT709GammaApple;
    
    let worked = mtkView.attach(player)
    if (worked == false)
    {
      NSLog("attach failed for AOVMTKView");
      return;
    }

  }

}

