import Image from "next/image"

export function DualPhoneShowcase() {
  return (
    <div className="relative mx-auto w-full max-w-5xl flex flex-col md:flex-row items-center justify-center gap-8 md:gap-16 py-12">
      {/* Phone 1 */}
      <div className="relative w-[280px] h-[580px] bg-black rounded-[45px] border-[8px] border-neutral-800 shadow-2xl ring-1 ring-white/20 overflow-hidden select-none z-10 transform md:-rotate-3 transition-transform hover:rotate-0 duration-500">
        {/* Dynamic Island */}
        <div className="absolute top-0 left-1/2 -translate-x-1/2 h-[30px] w-[100px] bg-black rounded-b-[18px] z-50">
          <div className="absolute top-[8px] right-[18px] h-1.5 w-1.5 rounded-full bg-[#1c1c1e] ring-1 ring-[#3a3a3c]" />
        </div>

        {/* Screen Content */}
        <div className="relative h-full w-full">
          <Image
            src="/images/WhatsApp Image 2025-11-23 at 20.24.05.jpeg"
            alt="Verified photo example"
            fill
            className="object-cover"
          />
        </div>
      </div>

      {/* Arrow Connection */}
      <div className="hidden md:block relative w-24 h-24 shrink-0">
        <svg className="w-full h-full text-white/50" viewBox="0 0 100 100" fill="none">
          <path
            d="M10,50 C30,50 30,80 50,80 C70,80 70,50 90,50"
            stroke="currentColor"
            strokeWidth="2"
            strokeDasharray="4 4"
          />
          <path d="M85,45 L95,50 L85,55" fill="currentColor" />
        </svg>
      </div>

      {/* Phone 2 */}
      <div className="relative w-[280px] h-[580px] bg-black rounded-[45px] border-[8px] border-neutral-800 shadow-2xl ring-1 ring-white/20 overflow-hidden select-none z-10 transform md:rotate-3 transition-transform hover:rotate-0 duration-500">
        {/* Dynamic Island */}
        <div className="absolute top-0 left-1/2 -translate-x-1/2 h-[30px] w-[100px] bg-black rounded-b-[18px] z-50">
          <div className="absolute top-[8px] right-[18px] h-1.5 w-1.5 rounded-full bg-[#1c1c1e] ring-1 ring-[#3a3a3c]" />
        </div>

        {/* Screen Content */}
        <div className="relative h-full w-full">
          <Image
            src="/images/WhatsApp Image 2025-11-23 at 20.24.15.jpeg"
            alt="Verified photo example"
            fill
            className="object-cover"
          />
        </div>
      </div>
    </div>
  )
}
