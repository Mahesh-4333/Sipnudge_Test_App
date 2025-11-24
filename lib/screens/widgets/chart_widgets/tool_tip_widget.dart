import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hydrify/constants/app_dimensions.dart';
import 'package:hydrify/constants/app_font_styles.dart';
import 'package:hydrify/cubit/ble/ble_cubit.dart';

class CustomChartToolTip extends StatelessWidget {
  const CustomChartToolTip({
    super.key,
    required this.percent,
    this.isPercent = true,
  });

  final num percent;
  final bool isPercent;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BleCubit, BleState>(
      builder: (context, state) {
        final data = state.waterHistory ?? [];

        if (data.isEmpty) {
          return const Text("No water history yet");
        }

        return ListView.builder(
          itemCount: data.length,
          itemBuilder: (context, index) {
            final entry = data[index];
            final double percent = (entry['goal'] != 0)
                ? (entry['consumed'] / entry['goal']) * 100
                : 0;

            return FittedBox(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SvgPicture.asset(
                    "assets/images/tooltip_image.svg",
                    width: AppDimensions.dim55.w,
                    height: AppDimensions.dim55.h,
                  ),
                  Positioned(
                    bottom: 24.h,
                    child: Text(
                      isPercent
                          ? "${percent.toStringAsFixed(0)}%"
                          : "${(entry['consumed'] / 1000).toStringAsFixed(1)}L",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: AppFontStyles.fontSize_10,
                        fontVariations: [
                          AppFontStyles.boldFontVariation,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
