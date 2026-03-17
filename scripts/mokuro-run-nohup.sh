#!/bin/bash
sudo -v
sudo -n nohup ~/homelab/scripts/mokuro-run.sh > ~/mokuro.log 2>&1 &
