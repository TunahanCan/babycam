(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const body = document.body;
  const header = document.querySelector("[data-header]");
  const menuToggle = document.querySelector("[data-menu-toggle]");
  const navigation = document.querySelector("[data-nav]");
  const progressBar = document.querySelector(".page-progress span");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  const menuLabel = (isOpen) => {
    const key = isOpen ? "menu.close" : "menu.open";
    const fallback = isOpen ? "Menüyü kapat" : "Menüyü aç";
    return window.MiuCamI18n?.t(key) || fallback;
  };

  const setMenuState = (isOpen, { moveFocus = false } = {}) => {
    if (!menuToggle || !navigation) return;

    menuToggle.setAttribute("aria-expanded", String(isOpen));
    menuToggle.setAttribute("aria-label", menuLabel(isOpen));
    navigation.classList.toggle("is-open", isOpen);
    body.classList.toggle("menu-open", isOpen);

    if (isOpen && moveFocus) {
      navigation.querySelector("a")?.focus();
    }
  };

  menuToggle?.addEventListener("click", () => {
    const nextState = menuToggle.getAttribute("aria-expanded") !== "true";
    setMenuState(nextState, { moveFocus: nextState });
  });

  const focusLinkedSection = (link) => {
    const url = new URL(link.href);
    if (
      !url.hash
      || url.origin !== window.location.origin
      || url.pathname !== window.location.pathname
    ) {
      return false;
    }

    let target;
    try {
      target = document.getElementById(decodeURIComponent(url.hash.slice(1)));
    } catch (_) {
      return false;
    }
    if (!target) return false;

    const hadTabIndex = target.hasAttribute("tabindex");
    if (!hadTabIndex) target.setAttribute("tabindex", "-1");
    window.requestAnimationFrame(() => {
      target.focus({ preventScroll: true });
      if (!hadTabIndex) {
        target.addEventListener("blur", () => target.removeAttribute("tabindex"), { once: true });
      }
    });
    return true;
  };

  navigation?.addEventListener("click", (event) => {
    const link = event.target.closest("a");
    if (!link) return;
    setMenuState(false);
    if (!desktopNavigation.matches) focusLinkedSection(link);
  });

  document.addEventListener("click", (event) => {
    if (
      menuToggle?.getAttribute("aria-expanded") === "true" &&
      !navigation?.contains(event.target) &&
      !menuToggle.contains(event.target)
    ) {
      setMenuState(false);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (menuToggle?.getAttribute("aria-expanded") !== "true") return;

    if (event.key === "Tab" && navigation) {
      const focusableItems = [menuToggle, ...navigation.querySelectorAll("a, button, select")];
      const firstItem = focusableItems[0];
      const lastItem = focusableItems[focusableItems.length - 1];

      if (event.shiftKey && document.activeElement === firstItem) {
        event.preventDefault();
        lastItem?.focus();
      } else if (!event.shiftKey && document.activeElement === lastItem) {
        event.preventDefault();
        firstItem?.focus();
      }
    }

    if (event.key === "Escape") {
      setMenuState(false);
      menuToggle.focus();
    }
  });

  const desktopNavigation = window.matchMedia("(min-width: 901px)");
  const closeDesktopMenu = (event) => {
    if (event.matches) setMenuState(false);
  };

  desktopNavigation.addEventListener?.("change", closeDesktopMenu);

  window.addEventListener("miucam:languagechange", () => {
    setMenuState(menuToggle?.getAttribute("aria-expanded") === "true");
  });

  let scrollTicking = false;
  const updateScrollState = () => {
    const scrollTop = window.scrollY;
    const scrollRange = document.documentElement.scrollHeight - window.innerHeight;
    const progress = scrollRange > 0 ? Math.min(scrollTop / scrollRange, 1) : 0;

    header?.classList.toggle("is-scrolled", scrollTop > 12);
    if (progressBar) progressBar.style.transform = `scaleX(${progress})`;
    scrollTicking = false;
  };

  window.addEventListener(
    "scroll",
    () => {
      if (scrollTicking) return;
      scrollTicking = true;
      window.requestAnimationFrame(updateScrollState);
    },
    { passive: true },
  );
  updateScrollState();

  const revealItems = [...document.querySelectorAll("[data-reveal]")];
  revealItems.forEach((item) => {
    const delay = Number.parseInt(item.dataset.revealDelay || "0", 10);
    item.style.setProperty("--reveal-delay", `${Math.max(delay, 0)}ms`);
  });
  document.documentElement.classList.add("reveal-ready");

  if (reducedMotion.matches || !("IntersectionObserver" in window)) {
    revealItems.forEach((item) => item.classList.add("is-visible"));
  } else {
    const revealObserver = new IntersectionObserver(
      (entries, observer) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8%", threshold: 0.06 },
    );

    revealItems.forEach((item) => revealObserver.observe(item));
  }

  const faqItems = [...document.querySelectorAll(".faq-list details")];
  faqItems.forEach((item) => {
    item.addEventListener("toggle", () => {
      if (!item.open) return;
      faqItems.forEach((otherItem) => {
        if (otherItem !== item) otherItem.open = false;
      });
    });
  });

  const sectionLinks = [...document.querySelectorAll('.primary-nav a[href^="#"]')];
  const observedSections = sectionLinks
    .map((link) => document.querySelector(link.getAttribute("href")))
    .filter(Boolean);

  if ("IntersectionObserver" in window && observedSections.length > 0) {
    const sectionObserver = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

        if (!visible) return;
        sectionLinks.forEach((link) => {
          const isCurrent = link.getAttribute("href") === `#${visible.target.id}`;
          link.classList.toggle("is-active", isCurrent);
          if (isCurrent) link.setAttribute("aria-current", "location");
          else link.removeAttribute("aria-current");
        });
      },
      { rootMargin: "-22% 0px -66%", threshold: [0, 0.2, 0.5] },
    );

    observedSections.forEach((section) => sectionObserver.observe(section));
  }

  document.querySelectorAll("[data-year]").forEach((year) => {
    year.textContent = String(new Date().getFullYear());
  });
})();
