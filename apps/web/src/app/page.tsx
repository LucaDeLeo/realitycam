export default function Home() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-zinc-50 font-sans dark:bg-black">
      <main className="flex min-h-screen w-full max-w-3xl flex-col items-center justify-center gap-8 px-16 py-32">
        <h1 className="text-4xl font-bold tracking-tight text-black dark:text-white">
          RealityCam
        </h1>
        <p className="max-w-md text-center text-lg text-zinc-600 dark:text-zinc-400">
          Verify the authenticity of photos captured with RealityCam
        </p>
        <div className="flex flex-col gap-4 text-base font-medium sm:flex-row">
          <a
            href="/verify/demo"
            className="flex h-12 items-center justify-center rounded-full bg-black px-6 text-white transition-colors hover:bg-zinc-800 dark:bg-white dark:text-black dark:hover:bg-zinc-200"
          >
            Verify a Photo
          </a>
        </div>
      </main>
    </div>
  );
}
