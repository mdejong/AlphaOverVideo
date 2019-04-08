//
//  ViewController.swift
//  AlienEscape
//
//  Created by Mo DeJong on 4/7/19.
//  Copyright © 2019 HelpURock. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
  
  @IBOutlet weak var bgImageView: UIImageView!
  
  override var prefersStatusBarHidden: Bool {
    return true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    assert(bgImageView != nil)
  }
}

