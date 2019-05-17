//
//  ViewController.swift
//  AlienEscape
//
//  Created by Mo DeJong on 4/7/19.
//  Copyright © Mo DeJong. All rights reserved.
//

import UIKit
import AlphaOverVideo

class ViewController: UIViewController {
  
  @IBOutlet weak var bgImageView: UIImageView!
  @IBOutlet weak var mtkView: AOVMTKView!
  
  @IBOutlet weak var chainsImageView: UIImageView!
  @IBOutlet weak var subviewBG: UIView!

  @IBOutlet weak var thankYouLabel: UILabel!
  
  var player: AOVPlayer?

  var tapCount : Int = 0
  
  override var prefersStatusBarHidden: Bool {
    return true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    assert(bgImageView != nil)
    assert(mtkView != nil)
    assert(chainsImageView != nil)
    assert(subviewBG != nil)
    assert(thankYouLabel != nil)
    
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
    
    thankYouLabel.layer.cornerRadius = 10;
    thankYouLabel.layer.masksToBounds = true;
  }
  
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    if touches.first != nil {
      if (self.tapCount == 0) {
        let alertController = UIAlertController(title: "HowTo", message: "Tap 10 times to free the alien!", preferredStyle: .alert)
        let defaultAction = UIAlertAction.init(title: "OK", style: .default, handler:{ (UIAlertAction) in
          // nop
        })
        alertController.addAction(defaultAction)
        self.present(alertController, animated: true, completion: nil)
      } else if (self.tapCount == 10) {
        // Free alien
        NSLog("Free The Alien!")
        
        if (true) {
          // Fade out the chains and the solid color background, rendering view will be completely transparent

          chainsImageView.alpha = 1.0
          subviewBG.alpha = 1.0
          
          thankYouLabel.isHidden = false
          thankYouLabel.alpha = 0.0
          
          UIView.beginAnimations(nil, context: nil)
          
          UIView.setAnimationDuration(9.0)
          //UIView.setAnimationRepeatCount(30)
          //UIView.setAnimationRepeatAutoreverses(true)
          chainsImageView.alpha = 0.0
          subviewBG.alpha = 0.0
          thankYouLabel.alpha = 1.0
          
          UIView.commitAnimations()
        }
      }
      
      self.tapCount += 1
    }
  }
  
}

