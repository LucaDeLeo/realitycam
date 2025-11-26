'use client';

import Script from 'next/script';

declare global {
  interface Window {
    Tally?: {
      loadEmbeds: () => void;
    };
  }
}

export function TallyEmbed() {
  return (
    <>
      <iframe
        data-tally-src="https://tally.so/embed/7RXKyZ?hideTitle=1&transparentBackground=1&dynamicHeight=1"
        loading="lazy"
        width="100%"
        height="276"
        frameBorder="0"
        marginHeight={0}
        marginWidth={0}
        title="Contact form"
      />
      <Script
        src="https://tally.so/widgets/embed.js"
        strategy="lazyOnload"
        onLoad={() => {
          if (typeof window !== 'undefined' && window.Tally) {
            window.Tally.loadEmbeds();
          }
        }}
      />
    </>
  );
}
