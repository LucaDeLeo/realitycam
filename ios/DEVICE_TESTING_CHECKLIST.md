# Device Testing Checklist - Rial Native iOS App

Test on: **iPhone Pro with LiDAR** (12 Pro or newer)

---

## 1. App Launch & Permissions

- [ ] App launches without crash
- [ ] Camera permission prompt appears on first launch
- [ ] Grant camera permission
- [ ] App shows AR camera preview (not the "LiDAR Required" screen)

---

## 2. Camera & Depth Capture

- [ ] Live camera feed displays correctly
- [ ] LiDAR depth overlay visible (colored depth visualization)
- [ ] Depth overlay opacity slider works (drag to adjust)
- [ ] Depth overlay toggle works (hide/show)
- [ ] Point camera at objects at different distances - depth colors change

---

## 3. Capture Flow

- [ ] Tap large capture button
- [ ] Haptic feedback felt on capture
- [ ] Capture preview sheet appears
- [ ] Preview shows captured photo
- [ ] "Retake" button dismisses and returns to camera
- [ ] "Use Photo" button saves capture

---

## 4. History Tab

- [ ] Tap "History" tab at bottom
- [ ] If no captures: empty state message shown
- [ ] After capture: thumbnail grid displays
- [ ] Thumbnails show correct photos
- [ ] Status badges visible (pending, uploading, etc.)
- [ ] Pull-to-refresh gesture works

---

## 5. Result Detail View

- [ ] Tap a capture thumbnail
- [ ] Detail view opens
- [ ] Photo displays with pinch-to-zoom
- [ ] Double-tap to zoom in/out
- [ ] Confidence badge shows (if verified)
- [ ] Evidence summary shows verification checks
- [ ] Share button works
- [ ] Back navigation works

---

## 6. Device Registration (Backend Required)

> Requires backend running at configured API URL

- [ ] App generates attestation key on first launch
- [ ] Registration request sent to backend
- [ ] Backend accepts attestation
- [ ] Device ID stored in Keychain

---

## 7. Upload Flow (Backend Required)

> Requires backend running at configured API URL

- [ ] Capture a photo and tap "Use Photo"
- [ ] Upload status shows "Uploading"
- [ ] Progress indicator visible
- [ ] Upload completes successfully
- [ ] Status changes to "Uploaded"
- [ ] Backend receives multipart upload
- [ ] Assertion verification passes on server

---

## 8. Offline & Background

- [ ] Enable airplane mode
- [ ] Capture a photo - saved locally
- [ ] Status shows "Pending"
- [ ] Disable airplane mode
- [ ] Upload resumes automatically
- [ ] Background upload: minimize app, upload continues
- [ ] Kill app during upload, reopen - upload resumes

---

## 9. Error Handling

- [ ] Revoke camera permission in Settings
- [ ] Reopen app - shows permission request view
- [ ] Simulate network error - retry logic activates
- [ ] Error messages display correctly

---

## 10. Performance

- [ ] Camera preview runs at smooth 60fps
- [ ] Depth overlay doesn't cause lag
- [ ] Capture is responsive (< 1 second)
- [ ] App doesn't overheat device excessively
- [ ] Memory usage stable (no leaks)

---

## Quick Smoke Test (5 minutes)

1. Launch app
2. Grant camera permission
3. See AR camera with depth overlay
4. Adjust depth opacity
5. Capture photo
6. Use photo
7. Go to History tab
8. See capture in grid
9. Tap to view detail
10. Pinch to zoom

**If all 10 steps work, basic functionality is confirmed!**

---

## Notes

- **API URL**: Configure in app or Info.plist
- **Backend**: Must be running for upload/registration tests
- **LiDAR**: Required - app won't work on non-Pro iPhones
- **iOS Version**: 15.0+ required
