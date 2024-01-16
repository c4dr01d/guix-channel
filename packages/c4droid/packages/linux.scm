(define-module (c4droid packages linux)
  #:use-module (gnu packages)
  #:use-module (gnu packages algebra)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages flex)
  #:use-module (gnu packages bison)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages elf)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages multiprecision)
  #:use-module (guix platform)
  #:use-module (guix build-system gnu)
  #:use-module (guix download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:export (customize-linux
	    make-defconfig))

(define* (customize-linux #:key name
			  (linux linux)
			  source
			  defconfig
			  (configs "")
			  extra-version)
  (package
    (inherit linux)
    (name (or name (package-name linux)))
    (source (or source (package-source linux)))
    (arguments
     (substitute-keyword-arguments
	 (package-arguments linux)
       ((#:imported-modules imported-modules %gnu-build-system-modules)
	`((guix build kconfig) ,@imported-modules))
       ((#:modules modules)
	`((guix build kconfig) ,@modules))
       ((#:phases phases)
	#~(modify-phases #$phases
	    (replace 'configure
	      (lambda* (#:key inputs #:allow-other-keys #:rest arguments)
		(setenv "EXTRAVERSION"
			#$(and extra-version
			       (not (string-null? extra-version))
			       (string-append "-" extra-version)))
		(let* ((configs (string-append "arch/" #$(linux-srcarch)
					       "/configs/"))
		       (guix_defconfig (string-append configs "guix_defconfig")))
		  #$(cond
		     ((not defconfig)
		      #~(begin
			  (apply (assoc-ref #$phases 'configure) arguments)
			  (invoke "make" "savedefconfig")
			  (rename-file "defconfig" guix_defconfig)))
		     ((string? defconfig)
		      #~(rename-file (string-append configs #$defconfig)
				     guix_defconfig))
		     (else
		      #~(copy-file #$defconfig guix_defconfig)))
		  (chmod guix_defconfig #o644)
		  (modify-defconfig guix_defconfig '#$configs)
		  (invoke "make" "guix_defconfig")
		  (verify-config ".config" guix_defconfig))))))))))

(define (make-defconfig uri sha256-as-base32)
  (origin (method uri-fetch)
	  (uri uri)
	  (sha256 (base32 sha256-as-base32))))

(define (linux-srcarch)
  (let ((linux-arch (platform-linux-architecture
		     (lookup-platform-by-target-or-system
		      (or (%current-target-system)
			  (%current-system))))))
    (match linux-arch
      ("i386" "x86")
      ("x86_64" "x86")
      ("sparc32" "sparc")
      ("sparc64" "sparc")
      ("sh64" "sh")
      (_ linux-arch))))

(define-public (system->defconfig system)
  (cond ((string-prefix? "powerpc-" system) "pmac32_defconfig")
	((string-prefix? "powerpc64-" system) "ppc64_defconfig")
	((string-prefix? "powerpc64le-" system) "ppc64_defconfig")
	(else "defconfig")))

(define (linux-urls version)
  (list (string-append "mirror://kernel.org/linux/kernel/v" (version-major version) ".x/linux-" version ".tar.xz")
	(string-append "https://mirrors.tuna.tsinghua.edu.cn/kernel/v" (version-major version) ".x/linux-" version ".tar.xz")
	(string-append "https://mirrors.ustc.edu.cn/kernel.org/linux/kernel/v" (version-major version) ".x/linux-" version ".tar.xz")))

(define (make-linux-headers version hash-string)
  (make-linux-headers* version (origin
				 (method url-fetch)
				 (uri (linux-urls version))
				 (sha256 (base32 hash-string)))))

(define (make-linux-headers* version source)
  (package
    (name "linux-headers")
    (version version)
    (source source)
    (build-system gnu-build-system)
    (native-inputs `(("perl" ,perl)
		     ,@(if (version>=? version "4.16")
			   `(("flex" ,flex)
			     ("bison" ,bison))
			   '())))
    (arguments
     `(#:modules ((guix build gnu-build-system)
		  (guix build utils)
		  (srfi srfi-1)
		  (ice-9 match))
       #:phases (modify-phases %standard-phases
		  (delete 'configure)
		  (replace 'build
		    (lambda _
		      (let ((arch ,(platform-linux-architecture
				    (lookup-platform-by-target-or-system
				     (or (%current-target-system)
					 (%current-system)))))
			    (defconfig ,(system->defconfig
					 (or (%current-target-system)
					     (%current-system))))
			    (make-target ,(if (version>=? version "5.3")
					      "headers"
					      "headers_check")))
			(setenv "ARCH" arch)
			(format #t "`ARCH' set to `~a'~%" (getenv "ARCH"))
			(invoke "make" defconfig)
			(invoke "make" "mrproper" make-target))))
		  (replace 'install
		    (lambda* (#:key outputs #:allow-other-keys)
		      (let ((out (assoc-ref outputs "out")))
			(for-each (lambda (file)
				    (let ((destination (string-append out "/include/" (match (string-split file #\/)
											((_ _ path ...)
											 (string-join path "/"))))))
				      (format #t "`~a' -> `~a'~%" file destination)
				      (install-file file (dirname destination))))
				  (find-files "usr/include" "\\.h$"))
			(mkdir (string-append out "/include/config"))
			(call-with-output-file (string-append out "/include/config/kernel.release")
			  (lambda (p)
			    (format p "~a-default~%" ,version)))))))
       #:allowed-references ()
       #:tests? #f))
    (supported-systems (delete "i586-gnu" %supported-systems))
    (home-page "https://kernel.org")
    (synopsis "GNU Linux kernel headers")
    (description "Headers of the Linux kernel.")
    (license license:gpl2)))

(define-public linux-6.6-source
  (origin
    (method url-fetch)
    (uri (linux-urls "6.6"))
    (sha256
     (base32 "1l2nisx9lf2vdgkq910n5ldbi8z25ky1zvl67zgwg2nxcdna09nr"))))

(define-public linux-headers-6.6
  (make-linux-headers* "6.6" linux-6.6-source))

(define* (kernel-config arch #:key variant)
  (let* ((name (string-append (if variant (string-append variant "-") "")
			      (if (string=? "i386" arch) "i686" arch) ".conf"))
	 (file (string-append "linux/" name))
	 (config (search-auxiliary-file file)))
    (and config (local-file config))))

(define %default-extra-linux-options
  `(;; Make the kernel config available at /proc/config.gz
    ("CONFIG_IKCONFIG" . #t)
    ("CONFIG_IKCONFIG_PROC" . #t)
    ;; Some very mild hardening.
    ("CONFIG_SECURITY_DMESG_RESTRICT" . #t)
    ;; All kernels should have NAMESPACES options enabled
    ("CONFIG_NAMESPACES" . #t)
    ("CONFIG_UTS_NS" . #t)
    ("CONFIG_IPC_NS" . #t)
    ("CONFIG_USER_NS" . #t)
    ("CONFIG_PID_NS" . #t)
    ("CONFIG_NET_NS" . #t)
    ;; Various options needed for elogind service:
    ;; https://issues.guix.gnu.org/43078
    ("CONFIG_CGROUP_FREEZER" . #t)
    ("CONFIG_BLK_CGROUP" . #t)
    ("CONFIG_CGROUP_WRITEBACK" . #t)
    ("CONFIG_CGROUP_SCHED" . #t)
    ("CONFIG_CGROUP_PIDS" . #t)
    ("CONFIG_CGROUP_FREEZER" . #t)
    ("CONFIG_CGROUP_DEVICE" . #t)
    ("CONFIG_CGROUP_CPUACCT" . #t)
    ("CONFIG_CGROUP_PERF" . #t)
    ("CONFIG_SOCK_CGROUP_DATA" . #t)
    ("CONFIG_BLK_CGROUP_IOCOST" . #t)
    ("CONFIG_CGROUP_NET_PRIO" . #t)
    ("CONFIG_CGROUP_NET_CLASSID" . #t)
    ("CONFIG_MEMCG" . #t)
    ("CONFIG_MEMCG_SWAP" . #t)
    ("CONFIG_MEMCG_KMEM" . #t)
    ("CONFIG_CPUSETS" . #t)
    ("CONFIG_PROC_PID_CPUSET" . #t)
    ;; Allow disk encryption by default
    ("CONFIG_DM_CRYPT" . m)
    ;; Support zram on all kernel configs
    ("CONFIG_ZSWAP" . #t)
    ("CONFIG_ZSMALLOC" . #t)
    ("CONFIG_ZRAM" . m)
    ;; Accessibility support.
    ("CONFIG_ACCESSIBILITY" . #t)
    ("CONFIG_A11Y_BRAILLE_CONSOLE" . #t)
    ("CONFIG_SPEAKUP" . m)
    ("CONFIG_SPEAKUP_SYNTH_SOFT" . m)
    ;; Modules required for initrd:
    ("CONFIG_NET_9P" . m)
    ("CONFIG_NET_9P_VIRTIO" . m)
    ("CONFIG_VIRTIO_BLK" . m)
    ("CONFIG_VIRTIO_NET" . m)
    ("CONFIG_VIRTIO_PCI" . m)
    ("CONFIG_VIRTIO_BALLOON" . m)
    ("CONFIG_VIRTIO_MMIO" . m)
    ("CONFIG_FUSE_FS" . m)
    ("CONFIG_CIFS" . m)
    ("CONFIG_9P_FS" . m)))

(define (config->string options)
  (string-join (map (match-lambda
		      ((option . 'm)
		       (string-append option "=m"))
		      ((option . #t)
		       (string-append option "=y"))
		      ((option . #f)
		       (string-append option "=n"))
		      ((option . string)
		       (string-append option "=\"" string "\"")))
		    options)
	       "\n"))

(define* (make-linux version hash-string supported-systems
		     #:key
		     (extra-version #f)
		     (configuration-file #f)
		     (defconfig "defconfig")
		     (extra-options %default-extra-linux-options))
  (make-linux* version
	       (origin
		 (method url-fetch)
		 (uri (linux-urls version))
		 (sha256 (base32 hash-string)))
	       supported-systems
	       #:extra-version extra-version
	       #:configuration-file configuration-file
	       #:defconfig defconfig
	       #:extra-options extra-options))

(define* (make-linux* version source supported-systems
		      #:key
		      (extra-version #f)
		      (configuration-file #f)
		      (defconfig "defconfig")
		      (extra-options %default-extra-linux-options))
  (package
    (name (if extra-version
	      (string-append "linux-" extra-version)
	      "linux"))
    (version version)
    (source source)
    (supported-systems supported-systems)
    (build-system gnu-build-system)
    (arguments
     (list
      #:modules '((guix build gnu-build-system)
		  (guix build utils)
		  (srfi srfi-1)
		  (srfi srfi-26)
		  (ice-9 ftw)
		  (ice-9 match))
      #:tests? #f
      #:phases #~(modify-phases %standard-phases
		   (add-after 'unpack 'patch-/bin/pwd
		     (lambda _
		       (substitute* (find-files "." "^Makefile(\\.include)?$")
			 (("/bin/pwd") "pwd"))))
		   (add-before 'configure 'set-environment
		     (lambda* (#:key target #:allow-other-keys)
		       (setenv "KCONFIG_NOTIMESTAMP" "1")
		       (setenv "KBUILD_BUILD_TIMESTAMP" (getenv "SOURCE_DATE_EPOCH"))

		       (setenv "KBUILD_BUILD_USER" "guix")
		       (setenv "KBUILD_BUILD_HOST" "guix")

		       (let ((arch #$(platform-linux-architecture
				      (lookup-platform-by-target-or-system
				       (or (%current-target-system)
					   (%current-system))))))
			 (setenv "ARCH" arch)
			 (format #t "`ARCH' set to `~a'~%" (getenv "ARCH"))
			 (when target
			   (setenv "CROSS_COMPILE" (string-append target "-"))
			   (format #t "`CROSS_COMPILE' set to `~a'~%"
				   (getenv "CROSS_COMPILE"))))

		       (substitute* "Makefile"
			 (("^ *EXTRAVERSION[[:blank:]]*=")
			  "EXTRAVERSION ?="))
		       (setenv "EXTRAVERSION"
			       #$(and extra-version
				      (string-append "-" extra-version)))))
		   (replace 'configure
		     (lambda _
		       (let ((config
			      #$(match (let ((arch (platform-linux-architecture
						    (lookup-platform-by-target-or-system
						     (or (%current-target-system)
							 (%current-system))))))
					 (and configuration-file arch
					      (configuration-file
					       arch
					       #:variant (version-major+minor version))))
				  (#f #f)
				  ((? file-like? config)
				   config))))
			 (if config
			     (begin
			       (copy-file config ".config")
			       (chmod ".config" #o666))
			     (invoke "make" #$defconfig))
			 (let ((port (open-file ".config" "a"))
			       (extra-configuration #$(config->string extra-options)))
			   (display extra-configuration port)
			   (close-port port))
			 (invoke "make" "oldconfig"))))
		   (replace 'install
		     (lambda _
		       (let ((moddir (string-append #$output "/lib/modules"))
			     (dtbdir (string-append #$output "/lib/dtbs")))
			 (for-each (lambda (file) (install-file file #$output))
				   (find-files "." "^(\\.config|bzImage|zImage|Image|vmlinuz|System\\.map|Module\\.symvers)$"))
			 (unless (null? (find-files "." "\\.dtb$"))
			   (mkdir-p dtbdir)
			   (invoke "make" (string-append "INSTALL_DTBS_PATH=" dtbdir)
				   "dtbs_install"))
			 (mkdir-p moddir)
			 (invoke "make"
				 "DEPMOD=true"
				 (string-append "MODULE_DIR=" moddir)
				 (string-append "INSTALL_PATH=" #$output)
				 (string-append "INSTALL_MOD_PATH=" #$output)
				 "INSTALL_MOD_STRIP=1"
				 "modules_install")
			 (let* ((versions (filter (lambda (name)
						    (not (string-prefix? "." name)))
						  (scandir moddir)))
				(version (match versions
					   ((x) x))))
			   (false-if-file-not-found
			    (delete-file
			     (string-append moddir "/" version "/build")))
			   (false-if-file-not-found
			    (delete-file
			     (string-append moddir "/" version "/source"))))))))))
    (native-inputs
     (list perl
	   bc
	   openssl
	   elfutils
	   flex
	   bison
	   util-linux
	   gmp
	   mpfr
	   mpc))
    (home-page "https://www.kernel.org")
    (synopsis "Linux kernel")
    (description "GNU Linux kernel.")
    (license license:gpl2)
    (properties '((max-silent-time . 10800)))))

(define-public linux-6.6
  (make-linux* "6.6"
	       linux-6.6-source
	       '("x86_64-linux")
	       #:configuration-file kernel-config))
