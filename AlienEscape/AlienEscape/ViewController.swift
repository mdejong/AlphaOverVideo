//
//  ViewController.swift
//  AlienEscape
//
//  Created by Mo DeJong on 4/7/19.
//  Copyright © 2019 HelpURock. All rights reserved.
//

import UIKit
import AlphaOverVideo

class ViewController: UIViewController {
  
  @IBOutlet weak var bgImageView: UIImageView!
  @IBOutlet weak var mtkView: AOVMTKView!
  
  var player: AOVPlayer?
  
  override var prefersStatusBarHidden: Bool {
    return true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    assert(bgImageView != nil)
    assert(mtkView != nil)
    
    mtkView.device = MTLCreateSystemDefaultDevice()
    
    if (mtkView.device == nil)
    {
      NSLog("Metal is not supported on this device");
      return;
    }
    
    // Generate RGBA pair or urls to seamless loop an infinite number of times
    let url1 = AOVPlayer.url(fromAsset:"Field.m4v")
    let url2 = AOVPlayer.url(fromAsset:"Field_alpha.m4v")
    assert(url1 != nil)
    assert(url2 != nil)
    let clips = [ [ url1, url2 ] ]
    
    let player = AOVPlayer.init(loopedClips:clips)
    self.player = player
    
    let worked = mtkView.attach(player)
    if (worked == false)
    {
      NSLog("attach failed for AOVMTKView");
      return;
    }

  }
}

