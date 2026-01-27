import "./styles/globals.css";
import { HeroVisualization } from "./components/HeroVisualization";
import { NetworkHUD } from "./components/NetworkHUD";
import { NetworkGlobe } from "./components/NetworkGlobe";
import { NetworkProvider } from "./contexts/NetworkContext";
import { useState, useEffect } from "react";

export default function App() {
  return (
    <NetworkProvider>
      <div className="min-h-screen bg-white dark:bg-black text-zinc-900 dark:text-zinc-100">
        <Hero />
        <div className="relative z-20 bg-white dark:bg-black">
          <BentoGrid />
          <HowItWorks />
          <GetStarted />
          <Footer />
        </div>
      </div>
    </NetworkProvider>
  );
}

function Hero() {
  const [scrollProgress, setScrollProgress] = useState(0);
  const [blurAmount, setBlurAmount] = useState(0);
  const [titleScrollProgress, setTitleScrollProgress] = useState(0);
  const [glowOpacity, setGlowOpacity] = useState(0);
  const [smokeAnimation, setSmokeAnimation] = useState({ x: 0, y: 0, intensity: 1 });

  useEffect(() => {
    // Wait 2 seconds, then fade in glow over 1.5 seconds
    const delayTimeout = setTimeout(() => {
      const startTime = Date.now();
      const fadeInDuration = 1500;

      const fadeInterval = setInterval(() => {
        const elapsed = Date.now() - startTime;
        const progress = Math.min(elapsed / fadeInDuration, 1);
        setGlowOpacity(progress);

        if (progress >= 1) {
          clearInterval(fadeInterval);
        }
      }, 16);
    }, 2000);

    return () => clearTimeout(delayTimeout);
  }, []);

  useEffect(() => {
    // Organic smoke-like animation
    let animationFrame: number;
    const startTime = Date.now();

    const animate = () => {
      const time = (Date.now() - startTime) / 1000;

      // Multiple sine waves at different frequencies for organic movement
      const x = Math.sin(time * 0.3) * 3 + Math.sin(time * 0.7) * 1.5;
      const y = Math.cos(time * 0.4) * 2 + Math.cos(time * 0.8) * 1;

      // Wax and wane intensity (breathing effect)
      const intensity = 0.85 + Math.sin(time * 0.5) * 0.15;

      setSmokeAnimation({ x, y, intensity });
      animationFrame = requestAnimationFrame(animate);
    };

    animate();
    return () => cancelAnimationFrame(animationFrame);
  }, []);

  useEffect(() => {
    const handleScroll = () => {
      const scrollY = window.scrollY;
      const viewportHeight = window.innerHeight;

      // Phase 1: Scroll hero content with blur (0 to 0.8vh)
      const heroScrollProgress = Math.min(scrollY / (viewportHeight * 0.8), 1);
      setBlurAmount(heroScrollProgress * 20); // 0 to 20px blur
      setTitleScrollProgress(heroScrollProgress); // 0 to 1 for character exit

      // Phase 2: After hero scrolled away, move camera for globe reveal (after 0.8vh, over 2vh)
      const cameraProgress = Math.max(0, Math.min(1, (scrollY - viewportHeight * 0.8) / (viewportHeight * 2)));
      setScrollProgress(cameraProgress);
    };

    window.addEventListener("scroll", handleScroll);
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return (
    <>
      {/* Interactive WebGL Background - Fixed */}
      <div
        className="fixed inset-0 z-0 transition-opacity duration-300"
        style={{
          // Fade out mesh completely by scrollProgress 0.3
          opacity: Math.max(0, 1 - (scrollProgress / 0.3))
        }}
      >
        <HeroVisualization
          className="w-full h-full"
          nodeCount={18}
          pulseFrequencyScale={1}
          appearanceRate={10}
          disappearanceRate={5}
          scrollProgress={scrollProgress}
        />
      </div>

      {/* Hero Content - Scrolls naturally with blur */}
      <section
        className="relative min-h-screen flex flex-col justify-center z-10"
        style={{ pointerEvents: titleScrollProgress >= 0.3 ? 'none' : 'auto' }}
      >
        <div
          className="max-w-[1200px] mx-auto text-center w-full px-6 pt-20"
          style={{
            filter: `blur(${blurAmount}px)`,
            opacity: Math.max(0, 1 - blurAmount / 15)
          }}
        >
        <div>
          <div className="inline-block mb-6 px-4 py-1.5 rounded-full border border-black/5 dark:border-white/10 bg-white/40 dark:bg-black/40 backdrop-blur-md text-[11px] font-semibold uppercase tracking-widest text-zinc-600 dark:text-zinc-400">
            Open Source • Distributed • Secure
          </div>

          <h1 className="text-7xl md:text-9xl lg:text-[10rem] font-bold tracking-tighter mb-8 leading-[0.85] text-zinc-900 dark:text-white flex flex-col items-center">
            <span className="flex items-center justify-center" style={{
              filter: `
                drop-shadow(${smokeAnimation.x * 0.5}px ${smokeAnimation.y * 0.5}px 10px rgba(255,255,255,${0.4 * glowOpacity * smokeAnimation.intensity}))
                drop-shadow(${smokeAnimation.x * 0.8}px ${smokeAnimation.y * 0.8}px 30px rgba(255,255,255,${0.3 * glowOpacity * smokeAnimation.intensity}))
                drop-shadow(${smokeAnimation.x * 1.2}px ${smokeAnimation.y * 1.2}px 60px rgba(255,255,255,${0.2 * glowOpacity * smokeAnimation.intensity}))
                drop-shadow(${smokeAnimation.x * 1.5}px ${smokeAnimation.y * 1.5}px 90px rgba(255,255,255,${0.15 * glowOpacity * smokeAnimation.intensity}))
                drop-shadow(${smokeAnimation.x * 2}px ${smokeAnimation.y * 2}px 120px rgba(255,255,255,${0.1 * glowOpacity * smokeAnimation.intensity}))
              `
            }}>
              {"Distributed.".split("").map((char, i) => {
                const totalChars = "Distributed.".length;
                const reverseIndex = totalChars - 1 - i;
                const charProgress = Math.max(0, (titleScrollProgress - (reverseIndex / totalChars) * 0.15) * 8);
                const translateY = -charProgress * 150;
                const opacity = Math.max(0, 1 - charProgress);

                return (
                  <span
                    key={i}
                    className="inline-block"
                    style={{
                      transform: `translateY(${translateY}px)`,
                      opacity: opacity,
                      transition: 'none'
                    }}
                  >
                    {char}
                  </span>
                );
              })}
            </span>
            <span className="flex items-center justify-center mt-2">
              {"Unlimited.".split("").map((char, i) => {
                const totalChars = "Unlimited.".length;
                const reverseIndex = totalChars - 1 - i;
                const charProgress = Math.max(0, (titleScrollProgress - (reverseIndex / totalChars) * 0.15) * 8);
                const translateY = -charProgress * 150;
                const opacity = Math.max(0, 1 - charProgress);

                return (
                  <span
                    key={i}
                    className="inline-block"
                    style={{
                      transform: `translateY(${translateY}px)`,
                      opacity: opacity,
                      transition: 'none'
                    }}
                  >
                    <span
                      className="inline-block animate-letter-rise bg-clip-text text-transparent pb-4 bg-[linear-gradient(8deg,rgba(79,70,229,0.5)_0%,rgba(129,140,248,0.8)_50%,rgba(79,70,229,0.5)_100%)]"
                      style={{
                        animationDelay: `${500 + i * 75}ms`
                      }}
                    >
                      {char}
                    </span>
                  </span>
                );
              })}
            </span>
          </h1>

          <p className="text-2xl md:text-3xl font-medium text-zinc-600 dark:text-zinc-300 max-w-2xl mx-auto mb-12" style={{ textShadow: '0 2px 8px rgba(0, 0, 0, 0.3)' }}>
            Turn your idle Mac into build credits.
            <br className="hidden md:block" />
            Build your Expo apps for free.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-5">
            <a href="#get-started" className="px-10 py-5 rounded-full bg-zinc-900 dark:bg-white text-white dark:text-black text-xl font-bold">
              Start Earning
            </a>
            <a href="#how-it-works" className="px-10 py-5 rounded-full bg-white/50 dark:bg-black/50 backdrop-blur-md border border-zinc-200 dark:border-zinc-800 text-zinc-900 dark:text-white text-xl font-bold">
              How it works
            </a>
          </div>

          <div className="mt-16">
            <NetworkHUD />
          </div>
        </div>
        </div>
      </section>

      {/* Camera Movement Spacer - provides scroll distance for globe reveal */}
      <div className="relative z-0" style={{ height: '200vh' }}>
        {/* NetworkGlobe - starts HUGE (inside view), shrinks to 2x (outside view) */}
        <div
          className="fixed inset-0 z-5 flex items-center justify-center pointer-events-none"
          style={{
            // Globe reaches 2x scale at 70% scroll, holds there for remaining 30%
            transform: `scale(${Math.max(2, 30 - scrollProgress * 40)})`,
            // Start invisible, only fade in after mesh is gone (scrollProgress > 0.3)
            // Fully visible by 70% scroll
            opacity: scrollProgress < 0.3 ? 0 : Math.min(0.7, (scrollProgress - 0.3) * 1.0),
          }}
        >
          <NetworkGlobe scrollProgress={scrollProgress} />
        </div>
      </div>
    </>
  );
}

function BentoGrid() {
  return (
    <section id="features" className="pt-32 pb-32 bg-white dark:bg-black relative z-10">
      <div className="max-w-[1200px] mx-auto px-6">
        <h2 className="text-4xl md:text-6xl font-semibold tracking-tighter mb-4 text-center">
          Power in numbers.
        </h2>
        <p className="text-xl text-zinc-500 text-center max-w-2xl mx-auto mb-16">
          A decentralized architecture designed for privacy, speed, and fairness.
        </p>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 auto-rows-[400px]">
          {/* Card 1: CPU (Large) */}
          <BentoCard
            colSpan="md:col-span-2"
            title="Idle Compute."
            subtitle="Your Mac sleeps while you grab coffee. Put that M-series chip to work."
            image="/assets/feature-cpu.png"
            dark
          />

          {/* Card 2: Security (Tall) */}
          <BentoCard
            colSpan="md:col-span-1"
            title="VM Isolated."
            subtitle="Hypervisor safety."
            image="/assets/feature-security.png"
          />

          {/* Card 3: Network (Full Width) */}
          <BentoCard
            colSpan="md:col-span-3"
            title="Community Mesh."
            subtitle="No servers to manage. No cloud bills. Just a peer-to-peer build network built by Expo developers just like you."
            image="/assets/feature-network.png"
            align="center"
          />
        </div>
      </div>
    </section>
  );
}

function BentoCard({
  colSpan,
  title,
  subtitle,
  image,
  dark,
  align = "left"
}: {
  colSpan: string;
  title: string;
  subtitle: string;
  image: string;
  dark?: boolean;
  align?: "left" | "center";
}) {
  return (
    <div
      className={`relative group overflow-hidden rounded-[2rem] border border-zinc-200 dark:border-zinc-800 ${colSpan} ${dark ? 'bg-black text-white' : 'bg-white dark:bg-zinc-900 text-zinc-900 dark:text-white'} hover:shadow-2xl transition-shadow duration-300`}
    >
      <div className="absolute inset-0 z-0 overflow-hidden">
        <img
          src={image}
          className="w-full h-full object-cover opacity-90 group-hover:scale-105 transition-transform duration-1000 ease-out"
          alt={title}
        />
        <div className={`absolute inset-0 bg-gradient-to-t ${dark ? 'from-black via-black/40 to-transparent' : 'from-white via-white/40 to-transparent dark:from-black dark:via-black/40'}`} />
      </div>

      <div className={`relative z-10 h-full flex flex-col justify-end p-10 ${align === 'center' ? 'items-center text-center' : 'items-start'}`}>
        <h3 className="text-4xl md:text-5xl font-semibold tracking-tighter mb-4 drop-shadow-sm">{title}</h3>
        <p className={`text-xl font-medium max-w-xl ${dark ? 'text-zinc-400' : 'text-zinc-600 dark:text-zinc-300'} drop-shadow-sm`}>{subtitle}</p>
      </div>
    </div>
  );
}

function HowItWorks() {
  return (
    <section id="how-it-works" className="py-32 bg-zinc-50 dark:bg-black px-6">
      <div className="max-w-[980px] mx-auto">
        <h2 className="text-4xl md:text-6xl font-semibold tracking-tighter mb-24 text-center">
          The Ecosystem.
        </h2>

        <div className="space-y-32 relative">
          {/* Connecting line */}
          <div className="absolute left-[2.4rem] top-8 bottom-8 w-0.5 bg-zinc-200 dark:bg-zinc-800 md:left-1/2 md:-ml-[1px]" />

          <Step
            num="01"
            title="The Controller"
            desc="The centralized brain of the operation. It manages the queue, tracks credits, and dispatches jobs to workers."
            side="left"
          />
          <Step
            num="02"
            title="The Worker"
            desc="A lightweight macOS menu bar app. It listens for jobs, securely spins up a fresh VM, runs the build, shuts down, and cleans up."
            side="right"
          />
          <Step
            num="03"
            title="The CLI"
            desc="Submit builds from your terminal. 'npx @sethwebster/expo-free-agent submit .'. Your credits are checked, your build is shipped."
            side="left"
          />
        </div>
      </div>
    </section>
  );
}

function Step({ num, title, desc, side }: { num: string; title: string; desc: string; side: "left" | "right" }) {
  return (
    <div className="relative flex flex-col md:flex-row gap-12 items-start">
      {/* Timeline Dot */}
      <div className="absolute left-[1.9rem] top-10 w-4 h-4 rounded-full bg-zinc-900 dark:bg-white ring-4 ring-white dark:ring-black md:left-1/2 md:-ml-2 z-10" />

      <div className={`flex-1 ${side === 'right' ? 'md:order-last md:pl-16' : 'md:text-right md:pr-16'} pl-20 md:pl-0`}>
        <div className="text-8xl font-bold text-zinc-200 dark:text-zinc-900 tracking-tighter absolute -top-10 -z-10 select-none opacity-50">{num}</div>
        <h3 className="text-3xl font-semibold mb-4">{title}</h3>
        <p className="text-xl md:text-2xl text-zinc-500 font-medium leading-relaxed tracking-tight text-balance">{desc}</p>
      </div>
      <div className="hidden md:block flex-1" />
    </div>
  );
}

function GetStarted() {
  return (
    <section id="get-started" className="py-32 bg-white dark:bg-zinc-950 px-6">
      <div className="max-w-[980px] mx-auto text-center">
        <h2 className="text-4xl md:text-6xl font-semibold tracking-tighter mb-8 text-zinc-900 dark:text-white">
          Ready to build?
        </h2>
        <p className="text-xl text-zinc-500 mb-12 font-medium">Submit your first build in seconds. No signup required.</p>

        <div className="grid md:grid-cols-2 gap-6 max-w-4xl mx-auto mb-12">
          <div className="bg-zinc-50 dark:bg-zinc-900/50 rounded-2xl border border-zinc-200 dark:border-zinc-800 p-8 shadow-xl text-left">
            <h3 className="text-lg font-semibold mb-4 text-zinc-900 dark:text-white">Submit a Build</h3>
            <div className="flex gap-2 mb-4 border-b border-zinc-200 dark:border-zinc-800 pb-3">
              <div className="w-2.5 h-2.5 rounded-full bg-red-500" />
              <div className="w-2.5 h-2.5 rounded-full bg-yellow-500" />
              <div className="w-2.5 h-2.5 rounded-full bg-green-500" />
            </div>
            <div className="font-mono text-sm space-y-3">
              <div className="flex gap-3 items-center">
                <span className="text-indigo-500 font-bold select-none">❯</span>
                <span className="text-zinc-700 dark:text-zinc-300">npx @sethwebster/expo-free-agent submit .</span>
              </div>
              <div className="flex gap-3 items-center opacity-60">
                <span className="text-zinc-400 select-none">#</span>
                <span className="text-zinc-500 dark:text-zinc-500 text-xs">pnpm dlx @sethwebster/expo-free-agent submit .</span>
              </div>
              <div className="flex gap-3 items-center opacity-60">
                <span className="text-zinc-400 select-none">#</span>
                <span className="text-zinc-500 dark:text-zinc-500 text-xs">bunx @sethwebster/expo-free-agent submit .</span>
              </div>
            </div>
          </div>

          <div className="bg-zinc-50 dark:bg-zinc-900/50 rounded-2xl border border-zinc-200 dark:border-zinc-800 p-8 shadow-xl text-left">
            <h3 className="text-lg font-semibold mb-4 text-zinc-900 dark:text-white">Earn Credits</h3>
            <div className="flex gap-2 mb-4 border-b border-zinc-200 dark:border-zinc-800 pb-3">
              <div className="w-2.5 h-2.5 rounded-full bg-red-500" />
              <div className="w-2.5 h-2.5 rounded-full bg-yellow-500" />
              <div className="w-2.5 h-2.5 rounded-full bg-green-500" />
            </div>
            <div className="font-mono text-sm space-y-3">
              <div className="flex gap-3 items-center">
                <span className="text-indigo-500 font-bold select-none">❯</span>
                <span className="text-zinc-700 dark:text-zinc-300">npx @sethwebster/expo-free-agent start</span>
              </div>
              <div className="flex gap-3 items-center opacity-60">
                <span className="text-zinc-400 select-none">#</span>
                <span className="text-zinc-500 dark:text-zinc-500 text-xs">pnpm dlx @sethwebster/expo-free-agent start</span>
              </div>
              <div className="flex gap-3 items-center opacity-60">
                <span className="text-zinc-400 select-none">#</span>
                <span className="text-zinc-500 dark:text-zinc-500 text-xs">bunx @sethwebster/expo-free-agent start</span>
              </div>
            </div>
          </div>
        </div>

        <p className="text-sm text-zinc-400 dark:text-zinc-500">
          Open source. MIT Licensed. <a href="https://github.com/expo/expo-free-agent" className="text-indigo-500 hover:text-indigo-600 transition-colors">View on GitHub →</a>
        </p>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="py-12 bg-zinc-50 dark:bg-black border-t border-zinc-200 dark:border-zinc-800">
      <div className="max-w-[980px] mx-auto px-6 flex flex-col md:flex-row justify-between items-center text-xs font-medium text-zinc-500 gap-4">
        <p>Before you build, you must first create the universe.</p>
        <div className="flex gap-6">
          <a href="https://github.com/expo/expo-free-agent" className="hover:text-zinc-900 dark:hover:text-white transition-colors">GitHub</a>
          <a href="https://twitter.com/expo" className="hover:text-zinc-900 dark:hover:text-white transition-colors">Twitter</a>
          <a href="https://expo.dev" className="hover:text-zinc-900 dark:hover:text-white transition-colors">Expo</a>
        </div>
      </div>
    </footer>
  );
}
