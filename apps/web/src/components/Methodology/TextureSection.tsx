/**
 * TextureSection - Explains texture classification methodology
 *
 * Content from PRD lines 348: Texture Classification using MobileNetV3 CNN
 * to distinguish real-world vs screen/print materials.
 */

/** Texture classification categories */
const TEXTURE_CATEGORIES = [
  {
    id: 'real_scene',
    name: 'Real Scene',
    description: 'Natural materials, textures, and lighting',
    examples: ['Skin, fabric, wood, concrete', 'Natural lighting variations', 'Complex material interactions'],
    indicator: 'GOOD - Supports authenticity',
    color: 'green',
  },
  {
    id: 'lcd_screen',
    name: 'LCD Screen',
    description: 'Liquid Crystal Display capture detected',
    examples: ['Backlight uniformity', 'RGB subpixel structure', 'Refresh artifacts'],
    indicator: 'SUSPICIOUS - Screen detected',
    color: 'red',
  },
  {
    id: 'oled_screen',
    name: 'OLED Screen',
    description: 'Organic LED Display capture detected',
    examples: ['Per-pixel lighting', 'Deep blacks', 'PenTile patterns'],
    indicator: 'SUSPICIOUS - Screen detected',
    color: 'red',
  },
  {
    id: 'printed_paper',
    name: 'Printed Paper',
    description: 'Printed material detected',
    examples: ['Halftone dot patterns', 'Paper texture', 'Ink bleeding'],
    indicator: 'SUSPICIOUS - Print detected',
    color: 'red',
  },
];

/**
 * TextureSection - Main content component
 */
export function TextureSection() {
  return (
    <div className="space-y-6">
      {/* What texture classification does */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          What is Texture Classification?
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          Texture classification uses a machine learning model (based on MobileNetV3)
          trained to distinguish between different material types. The model analyzes
          patterns at multiple scales to identify whether an image shows real-world
          materials or artificial surfaces like screens and prints.
        </p>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed mt-3">
          The model runs on-device using CoreML (iOS) or TensorFlow Lite (Android),
          ensuring fast processing without sending images to external servers.
        </p>
      </div>

      {/* Classifications */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Classification Categories
        </h3>
        <div className="space-y-3">
          {TEXTURE_CATEGORIES.map((category) => (
            <div
              key={category.id}
              className={`border rounded-lg p-4 ${
                category.color === 'green'
                  ? 'border-green-300 dark:border-green-700 bg-green-50 dark:bg-green-900/20'
                  : 'border-red-300 dark:border-red-700 bg-red-50 dark:bg-red-900/20'
              }`}
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="flex items-center gap-2">
                    <h4 className={`font-semibold ${
                      category.color === 'green'
                        ? 'text-green-800 dark:text-green-300'
                        : 'text-red-800 dark:text-red-300'
                    }`}>
                      {category.name}
                    </h4>
                    <code className="text-xs px-1.5 py-0.5 rounded bg-white/50 dark:bg-black/20 text-zinc-600 dark:text-zinc-400">
                      {category.id}
                    </code>
                  </div>
                  <p className={`text-sm mt-1 ${
                    category.color === 'green'
                      ? 'text-green-700 dark:text-green-400'
                      : 'text-red-700 dark:text-red-400'
                  }`}>
                    {category.description}
                  </p>
                  <ul className="mt-2 space-y-1">
                    {category.examples.map((example, i) => (
                      <li key={i} className={`text-xs ${
                        category.color === 'green'
                          ? 'text-green-600 dark:text-green-500'
                          : 'text-red-600 dark:text-red-500'
                      }`}>
                        - {example}
                      </li>
                    ))}
                  </ul>
                </div>
                <span className={`flex-shrink-0 text-xs px-2 py-1 rounded-full font-medium ${
                  category.color === 'green'
                    ? 'bg-green-200 dark:bg-green-800 text-green-800 dark:text-green-200'
                    : 'bg-red-200 dark:bg-red-800 text-red-800 dark:text-red-200'
                }`}>
                  {category.indicator}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* How the model was trained */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Model Training (High-Level)
        </h3>
        <div className="space-y-4">
          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900/50 flex items-center justify-center">
              <span className="text-sm font-semibold text-blue-600 dark:text-blue-400">1</span>
            </div>
            <div>
              <h4 className="font-medium text-zinc-900 dark:text-white">Dataset Collection</h4>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
                Training data includes thousands of images of real scenes, various screen types
                (LCD, OLED, monitors, TVs), and printed materials photographed under different
                lighting conditions.
              </p>
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900/50 flex items-center justify-center">
              <span className="text-sm font-semibold text-blue-600 dark:text-blue-400">2</span>
            </div>
            <div>
              <h4 className="font-medium text-zinc-900 dark:text-white">Feature Learning</h4>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
                The CNN learns to extract texture features at multiple scales - from fine
                details (pixel-level patterns) to coarse features (overall material appearance).
              </p>
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900/50 flex items-center justify-center">
              <span className="text-sm font-semibold text-blue-600 dark:text-blue-400">3</span>
            </div>
            <div>
              <h4 className="font-medium text-zinc-900 dark:text-white">Classification</h4>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
                The final layer outputs probability scores for each category. The highest
                probability determines the classification, with a confidence threshold
                applied for reliability.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Confidence threshold */}
      <div className="bg-zinc-50 dark:bg-zinc-800/50 p-4 rounded-lg">
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-2">
          Confidence Threshold
        </h3>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          Classifications are only trusted above a confidence threshold (typically 70%).
          Below this threshold, the result is marked as &quot;uncertain&quot; and does not negatively
          impact the overall confidence score. This prevents false positives from ambiguous
          images.
        </p>
      </div>

      {/* Limitations */}
      <div className="bg-yellow-50 dark:bg-yellow-900/20 border-l-4 border-yellow-500 p-4 rounded-r-lg">
        <h3 className="font-semibold text-yellow-800 dark:text-yellow-300 mb-2">
          Limitations
        </h3>
        <ul className="text-sm text-yellow-700 dark:text-yellow-400 space-y-2">
          <li>
            <strong>Adversarial Examples:</strong> Like all neural networks, the texture
            classifier is vulnerable to adversarial attacks. Carefully crafted images can
            fool the model into misclassifying screen captures as real scenes.
          </li>
          <li>
            <strong>Novel Materials:</strong> Unusual materials not well-represented in
            training data may be misclassified.
          </li>
          <li>
            <strong>High-Quality Prints:</strong> Professional photographic prints may
            be difficult to distinguish from real scenes.
          </li>
        </ul>
      </div>

      {/* Weight in confidence */}
      <div className="flex items-center justify-between p-3 bg-zinc-100 dark:bg-zinc-800 rounded-lg">
        <span className="text-sm text-zinc-600 dark:text-zinc-400">Weight in Confidence Calculation</span>
        <span className="text-sm font-semibold text-zinc-900 dark:text-white">15%</span>
      </div>
    </div>
  );
}
