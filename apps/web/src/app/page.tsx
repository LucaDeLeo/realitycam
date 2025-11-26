import Link from 'next/link';
import { Globe, CheckCircle2, Fingerprint, Shield, Scale, Camera, Share2, Ban, Lock, ArrowRight } from 'lucide-react';
import { FileDropzone } from '@/components/Upload/FileDropzone';
import { DualPhoneShowcase } from '@/components/Landing/DualPhoneShowcase';
import { TallyEmbed } from '@/components/Landing/TallyEmbed';

function AppleLogo({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className={className} xmlns="http://www.w3.org/2000/svg">
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2.156-.169-3.831 1.067-4.829 1.067zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.247-1.273 3.579 1.336.104 2.715-.688 3.559-1.567" />
    </svg>
  );
}

export default function Home() {
  return (
    <div className="min-h-screen bg-black text-white relative overflow-hidden">
      {/* Header */}
      <nav className="fixed top-0 left-0 right-0 z-50 border-b border-white/10 bg-black/20 backdrop-blur-md supports-backdrop-filter:bg-black/20">
        <div className="container mx-auto flex items-center justify-between px-6 py-4">
          <div className="flex items-center gap-2">
            <div className="h-8 w-8 rounded-lg bg-linear-to-br from-pink-500 via-white to-cyan-500" />
            <span className="text-xl font-bold tracking-tighter">rial.</span>
          </div>
          <Link
            href="#verify"
            className="group inline-flex h-10 items-center gap-2 rounded-full bg-white px-4 text-sm font-medium text-black transition-all hover:bg-white/90 hover:scale-105"
          >
            <span>Try the Verifier</span>
          </Link>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="container mx-auto px-6 pt-32 pb-24 flex flex-col items-center text-center">
        <div className="space-y-8 max-w-4xl mx-auto">
          <div className="inline-flex items-center rounded-full border border-white/10 bg-white/5 px-3 py-1 text-sm text-white/80 backdrop-blur-sm mb-4">
            <span className="flex h-2 w-2 rounded-full bg-yellow-500 mr-2 animate-pulse"></span>
            Building in public
          </div>

          <h1 className="text-5xl font-bold text-white md:text-7xl tracking-tighter drop-shadow-lg">
            Take a photo.<br />Prove it&apos;s real.
          </h1>

          <p className="mx-auto max-w-2xl text-xl font-medium text-white/80 leading-relaxed">
            Snap → Verify → Share. That&apos;s it.<br />
            <span className="text-white/60">Every photo gets a link anyone can check.</span>
          </p>

          <div className="flex flex-col items-center space-y-12 w-full pt-4">
            <Link
              href="#verify"
              className="inline-flex h-14 items-center gap-3 rounded-full bg-white px-8 text-black transition-all hover:bg-white/90 hover:scale-105 font-medium text-lg shadow-[0_0_40px_-10px_rgba(255,255,255,0.3)]"
            >
              <span>Try the Verifier</span>
            </Link>

            <div className="relative w-full max-w-5xl mx-auto mt-12 flex justify-center">
              {/* Glow effect behind phone */}
              <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[350px] h-[700px] bg-white/5 blur-[80px] rounded-full pointer-events-none" />
              <DualPhoneShowcase />
            </div>
          </div>
        </div>
      </section>

      {/* Value Proposition Section */}
      <section className="container mx-auto px-6 py-20">
        <div className="mx-auto max-w-5xl">
          <div className="text-center mb-16">
            <h2 className="text-4xl font-bold tracking-tight mb-4">We can&apos;t access your camera roll.</h2>
            <p className="text-lg text-neutral-400 max-w-2xl mx-auto">
              That&apos;s the point. Other apps let you upload anything. Rial only captures—no library, no editing, no way to fake it.
            </p>
          </div>

          <div className="grid gap-8 md:grid-cols-2">
            {/* No Editing Value Prop */}
            <div className="relative group">
              <div className="absolute inset-0 bg-linear-to-br from-pink-500/20 to-transparent rounded-2xl blur-xl opacity-0 group-hover:opacity-100 transition-opacity" />
              <div className="relative space-y-6 rounded-2xl border border-white/10 bg-black/60 p-8 backdrop-blur-md">
                <div className="flex items-center gap-4">
                  <div className="relative">
                    <div className="rounded-full bg-pink-500/10 p-4 ring-1 ring-pink-500/30">
                      <Camera className="h-8 w-8 text-pink-400" />
                    </div>
                    <div className="absolute -bottom-1 -right-1 rounded-full bg-black p-1">
                      <Lock className="h-4 w-4 text-pink-400" />
                    </div>
                  </div>
                  <h3 className="text-2xl font-bold">What you capture is what you share.</h3>
                </div>

                <p className="text-lg text-neutral-200 leading-relaxed">
                  The moment you tap the shutter, your photo is signed and uploaded. There&apos;s no step where you could edit it—that step doesn&apos;t exist.
                </p>

                <div className="flex items-center gap-3 pt-2">
                  <div className="flex items-center justify-center w-12 h-12 rounded-xl bg-white/5 border border-white/10">
                    <Camera className="h-5 w-5 text-white/60" />
                  </div>
                  <ArrowRight className="h-5 w-5 text-pink-400" />
                  <div className="flex items-center justify-center w-12 h-12 rounded-xl bg-white/5 border border-white/10">
                    <Lock className="h-5 w-5 text-white/60" />
                  </div>
                  <ArrowRight className="h-5 w-5 text-pink-400" />
                  <div className="flex items-center justify-center w-12 h-12 rounded-xl bg-pink-500/20 border border-pink-500/30">
                    <CheckCircle2 className="h-5 w-5 text-pink-400" />
                  </div>
                  <span className="text-sm text-neutral-400 ml-2">Instant</span>
                </div>

                <div className="pt-4 space-y-2 text-sm text-neutral-400 border-t border-white/5">
                  <div className="flex items-center gap-2">
                    <Ban className="h-4 w-4 text-red-400" />
                    <span>No camera roll access</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <Ban className="h-4 w-4 text-red-400" />
                    <span>No filters or editing tools</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Easy Sharing Value Prop */}
            <div className="relative group">
              <div className="absolute inset-0 bg-linear-to-br from-cyan-500/20 to-transparent rounded-2xl blur-xl opacity-0 group-hover:opacity-100 transition-opacity" />
              <div className="relative space-y-6 rounded-2xl border border-white/10 bg-black/60 p-8 backdrop-blur-md">
                <div className="flex items-center gap-4">
                  <div className="rounded-full bg-cyan-500/10 p-4 ring-1 ring-cyan-500/30">
                    <Share2 className="h-8 w-8 text-cyan-400" />
                  </div>
                  <h3 className="text-2xl font-bold">One link. Anyone can verify.</h3>
                </div>

                <p className="text-lg text-neutral-200 leading-relaxed">
                  Every photo gets a unique URL. Send it to a buyer, post it on social, attach it to a legal filing. One tap to see the proof.
                </p>

                {/* Mock URL Preview */}
                <div className="rounded-xl bg-black/80 border border-white/10 p-4 font-mono text-sm">
                  <div className="flex items-center gap-2 text-neutral-500 mb-2">
                    <Globe className="h-4 w-4" />
                    <span>Verification Link</span>
                  </div>
                  <div className="text-cyan-400 break-all">
                    rial.app/verify/<span className="text-white/60">a7f3x9...</span>
                  </div>
                </div>

                <div className="pt-4 space-y-2 text-sm text-neutral-400 border-t border-white/5">
                  <div className="flex items-center gap-2">
                    <CheckCircle2 className="h-4 w-4 text-green-400" />
                    <span>When it was taken</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <CheckCircle2 className="h-4 w-4 text-green-400" />
                    <span>Where it was taken</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <CheckCircle2 className="h-4 w-4 text-green-400" />
                    <span>That it&apos;s unedited</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <CheckCircle2 className="h-4 w-4 text-green-400" />
                    <span>That it came from a real device</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Statement Section */}
      <section id="mission" className="container mx-auto px-6 py-20">
        <div className="mx-auto max-w-4xl rounded-2xl border border-white/10 bg-black/40 p-8 backdrop-blur-md text-center">
          <h2 className="text-3xl font-bold mb-4">If it says rial., it&apos;s real.</h2>
          <p className="text-lg text-neutral-400">No edits. No fakes. No questions.</p>
        </div>
      </section>

      {/* Verify Section - FileDropzone Integration */}
      <section id="verify" className="container mx-auto px-6 py-20">
        <div className="mx-auto max-w-2xl space-y-8">
          <div className="text-center space-y-4">
            <h2 className="text-4xl font-bold tracking-tight">Try it yourself</h2>
            <p className="text-lg text-neutral-400">
              Drop any photo to check if it was captured with rial.
            </p>
          </div>

          <div className="rounded-2xl border border-white/10 bg-black/40 p-6 backdrop-blur-md">
            <FileDropzone />
          </div>

          <p className="text-center text-sm text-neutral-500">
            Want to see an example?{' '}
            <Link href="/verify/demo" className="text-pink-400 hover:text-pink-300 underline underline-offset-4">
              View Demo Verification
            </Link>
          </p>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="container mx-auto px-6 py-20">
        <div className="mx-auto max-w-6xl space-y-12">
          <div className="space-y-4 text-center md:text-left">
            <h2 className="text-4xl font-bold tracking-tight">Why you can trust it</h2>
            <p className="text-lg text-neutral-400">
              Multiple layers of proof, from hardware to software.
            </p>
          </div>
          <div className="grid gap-8 md:grid-cols-2">
            {/* Feature 1: Sensor-Level Authentication */}
            <div className="group space-y-4 rounded-xl border border-white/10 bg-black/40 p-8 backdrop-blur-md transition-all hover:bg-black/60 hover:border-pink-500/30">
              <div className="flex items-center gap-3">
                <div className="rounded-full bg-white/5 p-3 ring-1 ring-white/10">
                  <Fingerprint className="h-6 w-6 text-pink-400" />
                </div>
                <h3 className="text-xl font-semibold">Your iPhone proves it</h3>
              </div>
              <p className="text-neutral-200 leading-relaxed">
                Photos are cryptographically signed by your device&apos;s secure chip. Not software—hardware. We can prove this came from a real iPhone, not a PC.
              </p>
              <div className="pt-2 space-y-2 text-sm text-neutral-400">
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Secure Enclave signing</span>
                </div>
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Detects PC-generated fakes</span>
                </div>
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Tamper-proof signatures</span>
                </div>
              </div>
            </div>

            {/* Feature 2: LiDAR Depth Analysis */}
            <div className="group space-y-4 rounded-xl border border-white/10 bg-black/40 p-8 backdrop-blur-md transition-all hover:bg-black/60 hover:border-cyan-500/30">
              <div className="flex items-center gap-3">
                <div className="rounded-full bg-white/5 p-3 ring-1 ring-white/10">
                  <Shield className="h-6 w-6 text-cyan-400" />
                </div>
                <h3 className="text-xl font-semibold">3D depth says it&apos;s real</h3>
              </div>
              <p className="text-neutral-200 leading-relaxed">
                LiDAR captures real 3D depth alongside every photo. We analyze this to detect if you&apos;re photographing a screen or printout—not a real scene.
              </p>
              <div className="pt-2 space-y-2 text-sm text-neutral-400">
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Real 3D scene verification</span>
                </div>
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Catches photos of screens</span>
                </div>
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>iPhone Pro required</span>
                </div>
              </div>
            </div>

            {/* Feature 3: C2PA Standards */}
            <div className="group space-y-4 rounded-xl border border-white/10 bg-black/40 p-8 backdrop-blur-md transition-all hover:bg-black/60 hover:border-purple-500/30">
              <div className="flex items-center gap-3">
                <div className="rounded-full bg-white/5 p-3 ring-1 ring-white/10">
                  <Scale className="h-6 w-6 text-purple-400" />
                </div>
                <h3 className="text-xl font-semibold">Industry-standard proof</h3>
              </div>
              <p className="text-neutral-200 leading-relaxed">
                C2PA credentials embedded in every photo. Same standard used by Adobe, Microsoft, and newsrooms worldwide.
              </p>
              <div className="pt-2 space-y-2 text-sm text-neutral-400">
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Works with major platforms</span>
                </div>
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Tamper-evident</span>
                </div>
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Full provenance chain</span>
                </div>
              </div>
            </div>

            {/* Feature 4: Global Verification */}
            <div className="group space-y-4 rounded-xl border border-white/10 bg-black/40 p-8 backdrop-blur-md transition-all hover:bg-black/60 hover:border-yellow-300/30">
              <div className="flex items-center gap-3">
                <div className="rounded-full bg-white/5 p-3 ring-1 ring-white/10">
                  <Globe className="h-6 w-6 text-yellow-300" />
                </div>
                <h3 className="text-xl font-semibold">Verify from anywhere</h3>
              </div>
              <p className="text-neutral-200 leading-relaxed">
                Anyone with the link can check. No app needed, no account required. One tap, instant result.
              </p>
              <div className="pt-2 space-y-2 text-sm text-neutral-400">
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Works in any browser</span>
                </div>
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-400" />
                  <span>Downloadable evidence package</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Use Cases Section */}
      <section className="container mx-auto px-6 py-20">
        <div className="mx-auto max-w-5xl space-y-10">
          <h2 className="text-3xl font-bold">Use it for</h2>
          <div className="grid gap-6 md:grid-cols-3">
            {/* Everyday Use Cases */}
            <div className="space-y-4 rounded-lg border border-white/5 bg-white/5 p-6 backdrop-blur-sm hover:bg-white/10 transition-colors">
              <h3 className="text-lg font-semibold text-green-400">Sell faster</h3>
              <p className="text-sm text-neutral-400 leading-relaxed">
                Buyers trust verified photos. No more &quot;is this the actual item?&quot; back-and-forth.
              </p>
            </div>
            <div className="space-y-4 rounded-lg border border-white/5 bg-white/5 p-6 backdrop-blur-sm hover:bg-white/10 transition-colors">
              <h3 className="text-lg font-semibold text-rose-400">Stand out on dating apps</h3>
              <p className="text-sm text-neutral-400 leading-relaxed">
                One verified selfie says more than ten filtered ones. Prove you&apos;re real.
              </p>
            </div>
            <div className="space-y-4 rounded-lg border border-white/5 bg-white/5 p-6 backdrop-blur-sm hover:bg-white/10 transition-colors">
              <h3 className="text-lg font-semibold text-cyan-400">Prove you were there</h3>
              <p className="text-sm text-neutral-400 leading-relaxed">
                Concerts, trips, events—with proof, not just pixels.
              </p>
            </div>
            {/* Professional Use Cases */}
            <div className="space-y-4 rounded-lg border border-white/5 bg-white/5 p-6 backdrop-blur-sm hover:bg-white/10 transition-colors">
              <h3 className="text-lg font-semibold text-pink-400">Publish with proof</h3>
              <p className="text-sm text-neutral-400 leading-relaxed">
                Verified sources. Misinformation blocked. Trust restored.
              </p>
            </div>
            <div className="space-y-4 rounded-lg border border-white/5 bg-white/5 p-6 backdrop-blur-sm hover:bg-white/10 transition-colors">
              <h3 className="text-lg font-semibold text-yellow-300">Evidence that holds up</h3>
              <p className="text-sm text-neutral-400 leading-relaxed">
                Timestamp, location, device—all verified. Stands up in court.
              </p>
            </div>
            <div className="space-y-4 rounded-lg border border-white/5 bg-white/5 p-6 backdrop-blur-sm hover:bg-white/10 transition-colors">
              <h3 className="text-lg font-semibold text-purple-400">Document for the record</h3>
              <p className="text-sm text-neutral-400 leading-relaxed">
                Field work with immutable proof. Time, location, authenticity—locked in.
              </p>
            </div>
          </div>
        </div>
      </section>


      {/* Contact Section */}
      <section className="container mx-auto px-6 py-32 relative overflow-hidden">
        <div className="absolute inset-0 bg-linear-to-t from-pink-500/10 to-transparent pointer-events-none" />
        <div className="relative mx-auto max-w-2xl space-y-8 text-center">
          <h2 className="text-5xl font-bold text-balance drop-shadow-xl">Want early access?</h2>
          <p className="text-xl text-neutral-300 text-balance">
            Drop your email. We&apos;ll let you know when it&apos;s ready.
          </p>
          <div className="rounded-2xl border border-white/10 bg-black/40 p-6 backdrop-blur-md">
            <TallyEmbed />
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-white/10 bg-black/80 py-12 backdrop-blur-xl">
        <div className="container mx-auto px-6 text-center text-sm text-neutral-500">
          rial. — Photos that prove they&apos;re real.
        </div>
      </footer>
    </div>
  );
}
