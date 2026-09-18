## PRIDE DBAlign

**Multi-GNSS Precise-Product Day-Boundary Alignment Toolkit**

PRIDE DBAlign is used for the day-boundary discontinuity alignment of GNSS precise orbit/clock/bias products, developed by the PRIDE team (http://pride.apm.ac.cn). We make this software package open source with the goal of promoting the implementation of United Nations (UN) International Committee on GNSS (ICG) 2025 recommendation, "Continuous GNSS Time Transfer across Day Boundaries using IGS Products" (https://www.unoosa.org/documents/pdf/icg/2025/ICG-19/ICG-19_WG-D_Recommendation_B_.pdf). In particular, PRIDE DBAlign is able to align precise satellite products across day boundaries to keep ambiguities continuous beyond the midnight epochs. As a result, GNSS positioning and time/frequency transfer spanning days could be improved by avoiding day-boundary “jumps”. PRIDE DBAlign utilizes several library functions, header files, and table files from PRIDE PPP-AR (https://github.com/PrideLab/PRIDE-PPPAR), another open-source software developed by the same team.

The development of PRIDE DBAlign software is funded by the National Natural Science Foundation of China (Grant No. U25D8020) and supported by Sub-Commission 4.2 of the International Association of Geodesy (IAG), the Wuhan Combination Center (WCC), and the Bias & Ambiguity Resolution Committee (BAR) of the International GNSS Service (IGS).

The open-source software PRIDE DBAlign can be downloaded at https://github.com/PrideLab/PRIDE-DBAlign.
For the latest updates regarding support, and frequently asked questions (FAQs), please visit http://pride.apm.ac.cn/.
The copyright of this software package is protected under the GNU General Public License (version 3).

Relevant publications are

* Lin J, Geng J, Zhang Q (2025). Aligning GPS/Galileo/BDS satellite integer clock products across day boundaries for continuous time and frequency transfer. *J Geod* 99, 35. doi:[10.1007/s00190-025-01955-5](https://doi.org/10.1007/s00190-025-01955-5)
* Wen Q, Geng J, Deng Y, Zhang Y (2025). Validating the IGS products in mitigating day-boundary discontinuities of kinematic positioning and time transfer. *GPS Solut* 29, 170. doi:[10.1007/s10291-025-01929-2](https://doi.org/10.1007/s10291-025-01929-2)
* Geng J, Wang Y, Wen Q, Lin J, Tagliaferro G (2026). Quantifying all-frequency day-boundary discontinuities for GPS/Galileo/BDS satellite products. (*under review*)

PRIDE DBAlign is capable of performing day-boundary alignment on multi-GNSS precise clock/bias products to restore their cross-day continuity. It can be applied to research involving cross-day precise positioning and timing, such as geodesy and time transfer. The main features of PRIDE DBAlign include:

1) Support for GPS, Galileo, and BDS-2/3;
2) Support for the alignment of precise satellite products on baseline frequencies (*e.g.*, GPS L1/L2);
3) Provide a DOCB module in the Bias-SINEX format for day-boundary alignment residuals;
4) Aligned precise products are consistent with the latest IGS conventions: the Bias-SINEX bias file format;
5) An additional plotting function is provided to display day-boundary alignment residuals, facilitating data analysis for researchers.


## Contributors

### Developers
* Jianghui Geng, Yangyang Wang, Jihang Lin, Qiang Wen

### Testers
* Yingda Deng, Jiang Guo


## Version History

### 2026-09-18 (v1.0)

Release of **PRIDE DBAlign v1.0**


## Getting in Touch

* You can contact us for **bug reports** and **comments** by sending an email or leaving a message on our website:
  * Email: <pride@apm.ac.cn>
  * Website: <http://pride.apm.ac.cn>


## License

***Copyright (C) 2026 by SKLPG, CAS and Wuhan University, All rights reserved.***
