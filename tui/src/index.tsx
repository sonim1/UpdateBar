#!/usr/bin/env node
import React from 'react';
import {render} from 'ink';
import {App} from './App.js';

// Run in the alternate screen buffer when attached to a terminal. Besides
// keeping scrollback clean, this is required for Warp: without it Warp keeps
// its block input editor active and arrow keys never reach the app.
const useAltScreen = process.stdout.isTTY === true;
let altScreenActive = false;

function enterAltScreen() {
  if (!useAltScreen || altScreenActive) return;
  process.stdout.write('\u001B[?1049h');
  altScreenActive = true;
}

function leaveAltScreen() {
  if (!altScreenActive) return;
  process.stdout.write('\u001B[?1049l');
  altScreenActive = false;
}

enterAltScreen();
process.on('exit', leaveAltScreen);

const {waitUntilExit} = render(<App />);
waitUntilExit().finally(leaveAltScreen);
