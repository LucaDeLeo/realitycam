# RealityCam Mobile - Maestro E2E Tests

End-to-end tests for the RealityCam mobile app using [Maestro](https://maestro.mobile.dev/).

## Prerequisites

1. **Install Maestro CLI**:

   ```bash
   # macOS
   curl -Ls "https://get.maestro.mobile.dev" | bash

   # Verify installation
   maestro --version
   ```

2. **Physical iOS Device** (recommended):
   - RealityCam requires LiDAR and camera hardware
   - Simulator cannot test capture functionality
   - Connect device and trust computer

3. **Development Build**:

   ```bash
   cd apps/mobile
   npx expo prebuild --platform ios
   npx expo run:ios --device
   ```

## Running Tests

### Single Flow

```bash
# Run specific flow
maestro test .maestro/flows/example-flow.yaml

# Debug mode (step through)
maestro test --debug .maestro/flows/example-flow.yaml
```

### All Flows

```bash
# Run all flows in directory
maestro test .maestro/flows/

# With verbose output
maestro test .maestro/flows/ --format junit --output test-results/
```

### CI Mode

```bash
# Headless execution with output
maestro test .maestro/flows/ \
  --format junit \
  --output test-results/maestro-junit.xml \
  --no-ansi
```

## Test Structure

```
.maestro/
├── flows/                    # Test flows
│   ├── example-flow.yaml     # Sample flow (replace with real tests)
│   ├── capture-flow.yaml     # Photo capture E2E
│   ├── upload-flow.yaml      # Upload and queue E2E
│   └── verification-flow.yaml
├── config.yaml               # Global configuration (optional)
└── README.md                 # This file
```

## Writing Tests

### Flow Anatomy

```yaml
appId: com.realitycam.app  # Bundle ID

---
# Step 1: Launch
- launchApp:
    clearState: true

# Step 2: Assert UI
- assertVisible:
    id: "element-id"

# Step 3: Interact
- tapOn:
    id: "button-id"

# Step 4: Wait for async
- extendedWaitUntil:
    visible:
      id: "result-element"
    timeout: 10000
```

### Test IDs

Use `testID` prop in React Native components:

```tsx
<TouchableOpacity testID="capture-button">
  <Text>Capture</Text>
</TouchableOpacity>
```

Then reference in Maestro:

```yaml
- tapOn:
    id: "capture-button"
```

### Handling Permissions

```yaml
# iOS permission dialogs
- tapOn:
    text: "Allow"
    optional: true

- tapOn:
    text: "Allow While Using App"
    optional: true
```

## Best Practices

1. **Use `testID` attributes** - More stable than text matching
2. **Add `optional: true`** - For elements that may not always appear
3. **Use `extendedWaitUntil`** - For async operations (uploads, processing)
4. **Clear state between tests** - `clearState: true` in `launchApp`
5. **Test on real device** - Camera/LiDAR require hardware

## Troubleshooting

### "Element not found"

```yaml
# Add timeout and optional flag
- assertVisible:
    id: "element-id"
    timeout: 5000
    optional: true
```

### Permission dialogs blocking

```yaml
# Handle all common permission texts
- tapOn:
    text: "Allow"
    optional: true
- tapOn:
    text: "OK"
    optional: true
```

### App not launching

```bash
# Verify app is installed
maestro test --app-id com.realitycam.app .maestro/flows/example-flow.yaml

# Rebuild if needed
cd apps/mobile && npx expo run:ios --device
```

## Integration with CI

### GitHub Actions

```yaml
- name: Run Maestro Tests
  run: |
    curl -Ls "https://get.maestro.mobile.dev" | bash
    maestro test .maestro/flows/ --format junit --output test-results/

- name: Upload Results
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: maestro-results
    path: test-results/
```

## Knowledge Base References

- **test-levels-framework.md** - When to use E2E vs unit tests
- **test-quality.md** - Deterministic test design
- **selector-resilience.md** - Stable element selection
