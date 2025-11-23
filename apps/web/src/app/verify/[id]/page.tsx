interface VerifyPageProps {
  params: Promise<{ id: string }>;
}

export default async function VerifyPage({ params }: VerifyPageProps) {
  const { id } = await params;

  return (
    <div className="flex min-h-screen items-center justify-center bg-zinc-50 font-sans dark:bg-black">
      <main className="flex min-h-screen w-full max-w-4xl flex-col items-center justify-center gap-8 px-8 py-16">
        <h1 className="text-3xl font-bold tracking-tight text-black dark:text-white">
          Photo Verification
        </h1>
        <p className="text-lg text-zinc-600 dark:text-zinc-400">
          Verification ID: {id}
        </p>
        <div className="w-full max-w-2xl rounded-xl border border-zinc-200 bg-white p-8 dark:border-zinc-800 dark:bg-zinc-900">
          <p className="text-center text-zinc-500 dark:text-zinc-400">
            Verification results will appear here
          </p>
        </div>
      </main>
    </div>
  );
}
