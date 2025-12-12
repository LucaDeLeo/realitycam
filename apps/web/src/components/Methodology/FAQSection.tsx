'use client';

import { useState } from 'react';

interface FAQItem {
  question: string;
  answer: string;
  category: 'general' | 'technical' | 'trust';
}

/** FAQ items as specified in AC #13 */
const FAQ_ITEMS: FAQItem[] = [
  {
    question: 'What does HIGH confidence actually mean?',
    answer: 'HIGH confidence means the capture scored 85% or above AND hardware attestation passed. This indicates: (1) The device is genuine and unmodified, verified by Apple\'s Secure Enclave or Google\'s StrongBox. (2) The primary signal (LiDAR depth or multi-camera parallax) confirms a real 3D scene. (3) Supporting signals (Moire, texture, artifacts) agree with the primary signal. HIGH confidence does not mean 100% certainty - no system can guarantee that. It means multiple independent verification methods all support authenticity.',
    category: 'general',
  },
  {
    question: 'Can this be fooled?',
    answer: 'Yes, but it\'s difficult. Simple attacks (screenshots, photos of screens, basic editing) are reliably detected. Sophisticated attacks like the Chimera method can bypass AI detection algorithms, which is why we use an attestation-first model where hardware attestation is PRIMARY. To fully bypass rial., an attacker would need to: (1) Compromise Secure Enclave/StrongBox hardware (requires physical access and sophisticated tools), (2) Create a 3D physical replica of a scene (expensive and time-consuming), or (3) Find a zero-day in attestation protocols. These are nation-state level attacks, not practical for most scenarios.',
    category: 'trust',
  },
  {
    question: 'Why does my capture show MEDIUM confidence?',
    answer: 'MEDIUM confidence (60-85%) can occur for several reasons: (1) Some detection methods produced uncertain results (scores near decision boundaries). (2) Cross-validation found minor inconsistencies between methods. (3) Attestation passed but with a lower trust level (TEE instead of StrongBox on Android). (4) Environmental factors affected detection (unusual lighting, reflective surfaces). MEDIUM confidence doesn\'t mean the capture is fake - it means there\'s more uncertainty. Review the detailed breakdown to see which specific checks affected the score.',
    category: 'general',
  },
  {
    question: 'What is LiDAR and why does it matter?',
    answer: 'LiDAR (Light Detection and Ranging) is a sensor that measures distance using infrared light pulses. iPhone Pro models include a LiDAR scanner that creates precise 3D depth maps. LiDAR matters because: (1) It provides DIRECT physical measurements that cannot be spoofed by 2D screens or prints. (2) Real 3D scenes have multiple depth layers; screens are flat. (3) It\'s a hardware sensor, not software analysis, making it much harder to fool. (4) Combined with hardware attestation, it provides the strongest authenticity evidence available on mobile devices.',
    category: 'technical',
  },
  {
    question: 'Why is the Moire score 0% but still green?',
    answer: 'For Moire detection, a 0% score is GOOD - it means "no screen patterns detected." Unlike other metrics where higher is better, Moire detection looks for evidence of screens. No detection (0%) supports authenticity. A high Moire score (e.g., 80%) would be BAD, indicating likely screen capture. Think of it like a virus scan: "no viruses found" is the result you want. The green color indicates the result supports authenticity, not that the score is high.',
    category: 'technical',
  },
  {
    question: 'How is this different from AI deepfake detection?',
    answer: 'AI deepfake detection analyzes image content to find manipulation artifacts. rial. takes a fundamentally different approach: we verify PROVENANCE (where the capture came from) rather than analyzing content. Key differences: (1) We use hardware attestation to prove device identity - AI detection cannot do this. (2) We capture at the source with cryptographic binding - we don\'t analyze after-the-fact. (3) We measure physical properties (LiDAR depth) - AI detection analyzes pixels. (4) AI detection is vulnerable to adversarial attacks (Chimera) - hardware attestation is not. rial. verifies that a capture is authentic; AI detection tries to determine if content was manipulated. They solve different problems.',
    category: 'trust',
  },
  {
    question: 'Can I trust captures from Android devices?',
    answer: 'Yes, with some caveats. Android support varies by device: (1) StrongBox devices (Pixel 3+, Samsung S20+, flagship devices): These have hardware security comparable to iOS Secure Enclave. Trust level is HIGH. (2) TEE-only devices (most mid-range phones): These use software-isolated security. Better than nothing, but can be compromised by sophisticated OS-level attacks. Trust level is MEDIUM. (3) Android lacks LiDAR, so we use multi-camera parallax for depth - slightly less reliable than LiDAR. The confidence calculation accounts for these differences. A StrongBox Android capture can achieve HIGH confidence; a TEE-only device is capped at MEDIUM-HIGH.',
    category: 'trust',
  },
  {
    question: 'What happens if I capture a photo of a screen?',
    answer: 'Multiple detection methods will flag it: (1) LiDAR will see the flat screen surface (~0.3-0.5m uniform depth) instead of a 3D scene. (2) Moire detection may find interference patterns from screen pixels. (3) Texture classification may identify LCD/OLED material characteristics. (4) Artifact detection may find PWM flicker or specular reflections. The result will show LOW or SUSPICIOUS confidence with specific flags explaining what was detected. The capture is still recorded with its evidence - the verification page will clearly indicate it\'s likely not authentic.',
    category: 'general',
  },
];

/**
 * FAQItem component - Single expandable FAQ item
 */
function FAQItemComponent({ item, isOpen, onToggle }: { item: FAQItem; isOpen: boolean; onToggle: () => void }) {
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onToggle();
    }
  };

  return (
    <div className="border-b border-zinc-200 dark:border-zinc-700 last:border-b-0">
      <button
        type="button"
        onClick={onToggle}
        onKeyDown={handleKeyDown}
        aria-expanded={isOpen}
        className="w-full flex items-start justify-between gap-4 py-4 px-1 text-left
                   focus:outline-none focus:ring-2 focus:ring-inset focus:ring-blue-500 rounded"
      >
        <span className="font-medium text-zinc-900 dark:text-white pr-4">
          {item.question}
        </span>
        <svg
          className={`flex-shrink-0 w-5 h-5 text-zinc-500 dark:text-zinc-400 transition-transform duration-200 mt-0.5 ${
            isOpen ? 'rotate-180' : ''
          }`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M19 9l-7 7-7-7"
          />
        </svg>
      </button>
      <div
        className={`transition-all duration-300 ease-in-out overflow-hidden ${
          isOpen ? 'max-h-[1000px] opacity-100 pb-4' : 'max-h-0 opacity-0'
        }`}
      >
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed px-1">
          {item.answer}
        </p>
      </div>
    </div>
  );
}

/**
 * FAQSection - Accordion FAQ component for methodology page
 */
export function FAQSection() {
  const [openIndex, setOpenIndex] = useState<number | null>(null);

  const handleToggle = (index: number) => {
    setOpenIndex(openIndex === index ? null : index);
  };

  // Group FAQs by category for potential filtering
  const generalFAQs = FAQ_ITEMS.filter(item => item.category === 'general');
  const technicalFAQs = FAQ_ITEMS.filter(item => item.category === 'technical');
  const trustFAQs = FAQ_ITEMS.filter(item => item.category === 'trust');

  return (
    <div className="space-y-6">
      {/* General questions */}
      <div>
        <h3 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wide mb-3">
          General Questions
        </h3>
        <div className="bg-white dark:bg-zinc-900 rounded-lg border border-zinc-200 dark:border-zinc-700 divide-y divide-zinc-200 dark:divide-zinc-700">
          {generalFAQs.map((item) => (
            <FAQItemComponent
              key={item.question}
              item={item}
              isOpen={openIndex === FAQ_ITEMS.indexOf(item)}
              onToggle={() => handleToggle(FAQ_ITEMS.indexOf(item))}
            />
          ))}
        </div>
      </div>

      {/* Technical questions */}
      <div>
        <h3 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wide mb-3">
          Technical Questions
        </h3>
        <div className="bg-white dark:bg-zinc-900 rounded-lg border border-zinc-200 dark:border-zinc-700 divide-y divide-zinc-200 dark:divide-zinc-700">
          {technicalFAQs.map((item) => (
            <FAQItemComponent
              key={item.question}
              item={item}
              isOpen={openIndex === FAQ_ITEMS.indexOf(item)}
              onToggle={() => handleToggle(FAQ_ITEMS.indexOf(item))}
            />
          ))}
        </div>
      </div>

      {/* Trust questions */}
      <div>
        <h3 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wide mb-3">
          Trust & Security Questions
        </h3>
        <div className="bg-white dark:bg-zinc-900 rounded-lg border border-zinc-200 dark:border-zinc-700 divide-y divide-zinc-200 dark:divide-zinc-700">
          {trustFAQs.map((item) => (
            <FAQItemComponent
              key={item.question}
              item={item}
              isOpen={openIndex === FAQ_ITEMS.indexOf(item)}
              onToggle={() => handleToggle(FAQ_ITEMS.indexOf(item))}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
