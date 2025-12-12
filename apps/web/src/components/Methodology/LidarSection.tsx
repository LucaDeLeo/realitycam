/**
 * LidarSection - Explains LiDAR depth detection methodology
 *
 * Content from PRD lines 343-344 and docs/architecture.md:
 * LiDAR provides direct depth measurement via ARKit, the primary signal
 * for iOS Pro devices.
 */

/** Supported iPhone Pro models with LiDAR */
const SUPPORTED_DEVICES = [
  { model: 'iPhone 17 Pro / Pro Max', year: 2025, status: 'Current' },
  { model: 'iPhone 16 Pro / Pro Max', year: 2024, status: 'Supported' },
  { model: 'iPhone 15 Pro / Pro Max', year: 2023, status: 'Supported' },
  { model: 'iPhone 14 Pro / Pro Max', year: 2022, status: 'Supported' },
  { model: 'iPhone 13 Pro / Pro Max', year: 2021, status: 'Supported' },
  { model: 'iPhone 12 Pro / Pro Max', year: 2020, status: 'Supported' },
];

/**
 * DepthComparisonDiagram - Visual comparison of real scene vs flat surface
 */
function DepthComparisonDiagram() {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 my-4">
      {/* Real 3D Scene */}
      <div className="border border-green-300 dark:border-green-700 rounded-lg p-4 bg-green-50 dark:bg-green-900/20">
        <div className="flex items-center gap-2 mb-3">
          <span className="w-3 h-3 rounded-full bg-green-500" aria-hidden="true" />
          <h4 className="font-semibold text-green-800 dark:text-green-300">Real 3D Scene</h4>
        </div>
        {/* Simplified depth visualization */}
        <div className="relative h-24 bg-gradient-to-r from-zinc-200 via-zinc-400 to-zinc-600 dark:from-zinc-700 dark:via-zinc-500 dark:to-zinc-300 rounded overflow-hidden" aria-hidden="true">
          <div className="absolute inset-0 flex items-end justify-around px-2 pb-2">
            <div className="w-4 bg-green-500/70 h-8 rounded-t" />
            <div className="w-4 bg-green-500/70 h-16 rounded-t" />
            <div className="w-4 bg-green-500/70 h-12 rounded-t" />
            <div className="w-4 bg-green-500/70 h-20 rounded-t" />
            <div className="w-4 bg-green-500/70 h-6 rounded-t" />
          </div>
        </div>
        <p className="text-sm text-green-700 dark:text-green-400 mt-3">
          Multiple depth layers: Objects at varying distances create distinct depth measurements
        </p>
        <ul className="text-xs text-green-600 dark:text-green-500 mt-2 space-y-1">
          <li>- High depth variance (0.5-3.0+)</li>
          <li>- Multiple depth layers (10-50+)</li>
          <li>- Edge coherence with scene objects</li>
        </ul>
      </div>

      {/* Flat Surface (Screen/Print) */}
      <div className="border border-red-300 dark:border-red-700 rounded-lg p-4 bg-red-50 dark:bg-red-900/20">
        <div className="flex items-center gap-2 mb-3">
          <span className="w-3 h-3 rounded-full bg-red-500" aria-hidden="true" />
          <h4 className="font-semibold text-red-800 dark:text-red-300">Flat Surface (Screen/Print)</h4>
        </div>
        {/* Flat depth visualization */}
        <div className="relative h-24 bg-zinc-300 dark:bg-zinc-600 rounded overflow-hidden" aria-hidden="true">
          <div className="absolute inset-0 flex items-end justify-around px-2 pb-2">
            <div className="w-4 bg-red-500/70 h-10 rounded-t" />
            <div className="w-4 bg-red-500/70 h-10 rounded-t" />
            <div className="w-4 bg-red-500/70 h-10 rounded-t" />
            <div className="w-4 bg-red-500/70 h-10 rounded-t" />
            <div className="w-4 bg-red-500/70 h-10 rounded-t" />
          </div>
        </div>
        <p className="text-sm text-red-700 dark:text-red-400 mt-3">
          Uniform depth: Screen or print at single distance (typically 0.3-0.5m)
        </p>
        <ul className="text-xs text-red-600 dark:text-red-500 mt-2 space-y-1">
          <li>- Near-zero depth variance</li>
          <li>- Single depth layer</li>
          <li>- No edge coherence with scene</li>
        </ul>
      </div>
    </div>
  );
}

/**
 * LidarSection - Main content component
 */
export function LidarSection() {
  return (
    <div className="space-y-6">
      {/* What is LiDAR */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          What is LiDAR?
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          LiDAR (Light Detection and Ranging) is a sensor that measures distance by emitting
          infrared light pulses and measuring how long they take to return. iPhone Pro models
          include a LiDAR scanner that creates a precise 3D depth map of the scene in front
          of the camera.
        </p>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed mt-3">
          Unlike camera-based depth estimation, LiDAR provides direct physical measurements
          that cannot be fooled by displaying an image on a screen. The sensor sees through
          the display&apos;s image to measure the actual flat surface beneath.
        </p>
      </div>

      {/* Why LiDAR matters */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Why LiDAR is Valuable for Verification
        </h3>
        <DepthComparisonDiagram />
      </div>

      {/* Key metrics explained */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Key Metrics
        </h3>
        <div className="space-y-4">
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-4 rounded-lg">
            <div className="flex items-center justify-between mb-2">
              <h4 className="font-medium text-zinc-900 dark:text-white">Depth Variance</h4>
              <span className="text-xs text-zinc-500 dark:text-zinc-400">Weight: 55%</span>
            </div>
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              Measures how much depth values vary across the scene. Real 3D scenes have high
              variance (objects at different distances). Screens and prints have near-zero
              variance (everything at the same distance).
            </p>
          </div>

          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-4 rounded-lg">
            <div className="flex items-center justify-between mb-2">
              <h4 className="font-medium text-zinc-900 dark:text-white">Depth Layers</h4>
              <span className="text-xs text-zinc-500 dark:text-zinc-400">Typical: 10-50+</span>
            </div>
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              Counts distinct depth clusters in the scene. A real room might have 30+ layers
              (floor, furniture, walls, people). A screen capture has 1-3 layers (screen
              surface, any foreground objects, background).
            </p>
          </div>

          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-4 rounded-lg">
            <div className="flex items-center justify-between mb-2">
              <h4 className="font-medium text-zinc-900 dark:text-white">Edge Coherence</h4>
              <span className="text-xs text-zinc-500 dark:text-zinc-400">Range: 0-1</span>
            </div>
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              Measures how well depth edges align with visual edges in the RGB image.
              In real scenes, object boundaries match depth discontinuities. When photographing
              a screen, the RGB edges (from the displayed image) do not match depth edges
              (the flat screen surface).
            </p>
          </div>
        </div>
      </div>

      {/* Limitations */}
      <div className="bg-yellow-50 dark:bg-yellow-900/20 border-l-4 border-yellow-500 p-4 rounded-r-lg">
        <h3 className="font-semibold text-yellow-800 dark:text-yellow-300 mb-2">
          Limitations
        </h3>
        <ul className="text-sm text-yellow-700 dark:text-yellow-400 space-y-2">
          <li>
            <strong>3D Physical Replicas:</strong> LiDAR cannot distinguish a real scene from
            a carefully constructed 3D physical replica. If someone builds a miniature set,
            LiDAR will see real 3D depth.
          </li>
          <li>
            <strong>Range:</strong> LiDAR works best at 0.5-5 meters. Very distant scenes may
            have reduced accuracy.
          </li>
          <li>
            <strong>Reflective surfaces:</strong> Mirrors and highly reflective surfaces can
            confuse depth measurements.
          </li>
        </ul>
      </div>

      {/* Device support */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Supported Devices
        </h3>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-3">
          LiDAR is available on iPhone Pro models only:
        </p>
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-200 dark:border-zinc-700">
                <th className="text-left py-2 pr-4 font-medium text-zinc-900 dark:text-white">Model</th>
                <th className="text-left py-2 pr-4 font-medium text-zinc-900 dark:text-white">Year</th>
                <th className="text-left py-2 font-medium text-zinc-900 dark:text-white">Status</th>
              </tr>
            </thead>
            <tbody>
              {SUPPORTED_DEVICES.map((device) => (
                <tr key={device.model} className="border-b border-zinc-100 dark:border-zinc-800">
                  <td className="py-2 pr-4 text-zinc-700 dark:text-zinc-300">{device.model}</td>
                  <td className="py-2 pr-4 text-zinc-600 dark:text-zinc-400">{device.year}</td>
                  <td className="py-2">
                    <span className={`text-xs px-2 py-0.5 rounded-full ${
                      device.status === 'Current'
                        ? 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300'
                        : 'bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400'
                    }`}>
                      {device.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
