//
//  SplashViewController.swift
//
//  Created by Mo DeJong on 5/7/19.
//  Copyright © 2019 HelpURock. All rights reserved.
//

import UIKit

class SplashViewController: UIViewController {

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view.
    
    let delaySeconds = 4.0
    DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
      self.launchIntroVideo()
    }
  }

  func launchIntroVideo() {
    print("launchIntroVideo")
  }
}

