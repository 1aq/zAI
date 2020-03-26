﻿﻿unit LargeMetricImgClassifierFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation,
  FMX.StdCtrls, FMX.Objects, FMX.ScrollBox, FMX.Memo, FMX.Layouts, FMX.ExtCtrls,
  System.Threading,

  System.IOUtils,

  CoreClasses, ListEngine,
  KDTree,
  zAI, zAI_Common, zAI_TrainingTask,
  zDrawEngineInterface_SlowFMX, zDrawEngine, Geometry2DUnit, MemoryRaster,
  MemoryStream64, PascalStrings, UnicodeMixedLib, DoStatusIO;

type
  TLargeMetricImgClassifierForm = class(TForm)
    Training_IMGClassifier_Button: TButton;
    Memo1: TMemo;
    Timer1: TTimer;
    ResetButton: TButton;
    TestClassifierButton: TButton;
    procedure TestClassifierButtonClick(Sender: TObject);
    procedure Training_IMGClassifier_ButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ResetButtonClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    procedure DoStatusMethod(Text_: SystemString; const ID: Integer);
  public
    ai: TAI;
    imgMat: TAI_ImageMatrix;

    // 大规模训练会直接绕过内存使用，让数据以序列化方式通过Stream来工作
    // TRasterSerialized应该构建在ssd,m2,raid这类拥有高速存储能力的设备中
    RSeri: TRasterSerialized;
  end;

var
  LargeMetricImgClassifierForm: TLargeMetricImgClassifierForm;

implementation

{$R *.fmx}


procedure TLargeMetricImgClassifierForm.TestClassifierButtonClick(Sender: TObject);
begin
  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    var
      i, j: Integer;
      pick_raster: Integer;
      imgL: TAI_ImageList;
      img: TAI_Image;
      rasterList: TMemoryRasterList;

      output_fn, matrix_learn_fn: U_String;
      hnd: TMDNN_Handle;
      vec: TKDTree_Vec;
      KD: TKDTree;
      wrong: Integer;
    begin
      output_fn := umlCombineFileName(TPath.GetLibraryPath, 'LMetric_mnist_number_0_9' + C_LMetric_Ext);
      matrix_learn_fn := umlCombineFileName(TPath.GetLibraryPath, 'LMetric_mnist_number_0_9.matrix');

      if (not umlFileExists(output_fn)) or (not umlFileExists(matrix_learn_fn)) then
        begin
          DoStatus('必须训练');
          exit;
        end;

      TThread.Synchronize(Sender, procedure
        begin
          Training_IMGClassifier_Button.Enabled := False;
          TestClassifierButton.Enabled := False;
          ResetButton.Enabled := False;
        end);

      KD := TKDTree.Create(C_LMetric_Dim);
      KD.LoadFromFile(matrix_learn_fn);
      // ZAI对cuda的支持机制说明：在10.x版本，一个ZAI进程一次只能用一个cuda，不能并行化使用cuda，如果有多种cuda计算多开进程即可
      // 使用zAI的cuda必行保证在主进程中计算，否则会发生显存泄漏
      TThread.Synchronize(TThread.CurrentThread, procedure
        begin
          hnd := ai.LMetric_ResNet_Open_Stream(output_fn);
        end);

      // 在每个分类中，随机采集出来测试的数量
      pick_raster := 100;

      // 从训练数据集中随机构建测试数据集
      rasterList := TMemoryRasterList.Create;
      for i := 0 to imgMat.Count - 1 do
        begin
          imgL := imgMat[i];
          for j := 0 to pick_raster - 1 do
            begin
              img := imgL[umlRandomRange(0, imgL.Count - 1)];
              rasterList.Add(img.Raster);
              rasterList.Last.UserToken := imgL.FileInfo;
            end;
        end;

      wrong := 0;
      for i := 0 to rasterList.Count - 1 do
        begin
          // ZAI对cuda的支持机制说明：在10.x版本，一个ZAI进程一次只能用一个cuda，不能并行化使用cuda，如果有多种cuda计算多开进程即可
          // 使用zAI的cuda必行保证在主进程中计算，否则会发生显存泄漏
          TThread.Synchronize(TThread.CurrentThread, procedure
            begin
              vec := ai.LMetric_ResNet_Process(hnd, rasterList[i]);
            end);
          if not SameText(rasterList[i].UserToken, KD.SearchToken(vec)) then
              inc(wrong);
        end;
      DoStatus('测试总数: %d', [rasterList.Count]);
      DoStatus('测试错误: %d', [wrong]);
      DoStatus('模型准确率: %f%%', [(1.0 - (wrong / rasterList.Count)) * 100]);

      DisposeObject(rasterList);
      ai.LMetric_ResNet_Close(hnd);
      DisposeObject(KD);

      DoStatus('正在回收内存');
      imgMat.SerializedAndRecycleMemory(RSeri);

      TThread.Synchronize(Sender, procedure
        begin
          Training_IMGClassifier_Button.Enabled := True;
          TestClassifierButton.Enabled := True;
          ResetButton.Enabled := True;
        end);
      DoStatus('测试完成.');
    end);
end;

procedure TLargeMetricImgClassifierForm.Training_IMGClassifier_ButtonClick(Sender: TObject);
begin
  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    var
      param: PMetric_ResNet_Train_Parameter;
      sync_fn, output_fn, matrix_learn_fn: U_String;
      hnd: TMDNN_Handle;
      kdDataList: TKDTreeDataList;
      KD: TKDTree;
    begin
      TThread.Synchronize(Sender, procedure
        begin
          Training_IMGClassifier_Button.Enabled := False;
          TestClassifierButton.Enabled := False;
          ResetButton.Enabled := False;
        end);

      sync_fn := umlCombineFileName(TPath.GetLibraryPath, 'LMetric_mnist_number_0_9.imgMat.sync');
      output_fn := umlCombineFileName(TPath.GetLibraryPath, 'LMetric_mnist_number_0_9' + C_LMetric_Ext);
      matrix_learn_fn := umlCombineFileName(TPath.GetLibraryPath, 'LMetric_mnist_number_0_9.matrix');

      if (not umlFileExists(output_fn)) or (not umlFileExists(matrix_learn_fn)) then
        begin
          param := TAI.Init_LMetric_ResNet_Parameter(sync_fn, output_fn);

          // 本次训练计划使用8小时
          param^.timeout := C_Tick_Hour * 8;

          // 收敛幅度
          param^.learning_rate := 0.01;
          param^.completed_learning_rate := 0.00001;

          // 收敛梯度的处理条件
          // 在收敛梯度中，只要失效步数高于该数值，梯度就会开始收敛
          param^.iterations_without_progress_threshold := 300;

          // 请参考od思路
          // resnet每次做step时的光栅输入批次
          // 根据gpu和内存的配置来设定即可
          // 以下参数，需要6G显存才能运行，显存不够，可自行改小
          param^.step_mini_batch_target_num := 10;
          param^.step_mini_batch_raster_num := 20;

          // gpu每做一次批次运算会暂停的时间单位是ms
          // 这项参数是在1.15新增的呼吸参数，它可以让我们在工作的同时，后台进行无感觉训练
          // zAI.KeepPerformanceOnTraining := 10;

          // 在大规模训练中，使用频率不高的光栅化数据数据都会在硬盘(m2,ssd,raid)暂存，使用才会被调用出来
          // LargeScaleTrainingMemoryRecycleTime表示这些光栅化数据可以在系统内存中暂存多久，单位是毫秒，数值越大，越吃内存
          // 如果在机械硬盘使用光栅序列化交换，更大的数值可能带来更好的训练性能
          // 大规模训练注意给光栅序列化交换文件腾挪足够的磁盘空间
          // 大数据消耗到数百G甚至若干TB，因为某些jpg这类数据原太多，展开以后，存储空间会在原尺度基础上*10倍左右
          LargeScaleTrainingMemoryRecycleTime := C_Tick_Second * 5;

          if ai.LMetric_ResNet_Train(True, True, RSeri, imgMat, param) then
            begin
              DoStatus('训练成功.');
              kdDataList := TKDTreeDataList.Create;
              hnd := ai.LMetric_ResNet_Open_Stream(output_fn);
              DoStatus('正在使用metric将image翻译成k向量.');
              ai.LMetric_ResNet_SaveToKDTree(hnd, True, imgMat, kdDataList);
              DoStatus('k向量训练，秒完.');
              KD := TKDTree.Create(zAI.C_LMetric_Dim);
              kdDataList.Build(KD);
              DisposeObject(kdDataList);
              KD.SaveToFile(matrix_learn_fn);
              DisposeObject(KD);
              ai.LMetric_ResNet_Close(hnd);
            end
          else
            begin
              DoStatus('训练失败.');
            end;

          TAI.Free_LMetric_ResNet_Parameter(param);
        end
      else
          DoStatus('图片分类器已经训练过了.');

      TThread.Synchronize(Sender, procedure
        begin
          Training_IMGClassifier_Button.Enabled := True;
          TestClassifierButton.Enabled := True;
          ResetButton.Enabled := True;
        end);
    end);
end;

procedure TLargeMetricImgClassifierForm.DoStatusMethod(Text_: SystemString; const ID: Integer);
begin
  Memo1.Lines.Add(Text_);
  Memo1.GoToTextEnd;
end;

procedure TLargeMetricImgClassifierForm.FormCreate(Sender: TObject);
begin
  AddDoStatusHook(Self, DoStatusMethod);
  // 读取zAI的配置
  ReadAIConfig;
  // 这一步会连接Key服务器，验证ZAI的Key
  // 连接服务器验证Key是在启动引擎时一次性的验证，只会当程序启动时才会验证，假如验证不能通过，zAI将会拒绝工作
  // 在程序运行中，反复创建TAI，不会发生远程验证
  // 验证需要一个userKey，通过userkey推算出ZAI在启动时生成的随机Key，userkey可以通过web申请，也可以联系作者发放
  // 验证key都是抗量子级，无法被破解
  zAI.Prepare_AI_Engine();

  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    var
      tokens: TArrayPascalString;
      i, j: Integer;
      imgL: TAI_ImageList;
      detDef: TAI_DetectorDefine;
      n: TPascalString;
    begin
      TThread.Synchronize(Sender, procedure
        begin
          Training_IMGClassifier_Button.Enabled := False;
          TestClassifierButton.Enabled := False;
          ResetButton.Enabled := False;
        end);
      ai := TAI.OpenEngine();
      imgMat := TAI_ImageMatrix.Create;
      DoStatus('正在读取分类图片矩阵库.');
      // TRasterSerialized 创建时需要指定一个临时文件名，ai.MakeSerializedFileName指向了一个临时目录temp，它一般位于c:盘
      // 如果c:盘空间不够，训练大数据将会出错，解决办法，重新指定TRasterSerialized构建的临时文件名
      RSeri := TRasterSerialized.Create(TFileStream.Create(ai.MakeSerializedFileName, fmCreate));
      imgMat.LargeScale_LoadFromFile(RSeri, umlCombineFileName(TPath.GetLibraryPath, 'mnist_number_0_9.imgMat'));

      DoStatus('矫正分类标签.');
      for i := 0 to imgMat.Count - 1 do
        begin
          imgL := imgMat[i];
          imgL.CalibrationNullToken(imgL.FileInfo);
          for j := 0 to imgL.Count - 1 do
            if imgL[j].DetectorDefineList.Count = 0 then
              begin
                detDef := TAI_DetectorDefine.Create(imgL[j]);
                detDef.R := imgL[j].Raster.BoundsRect;
                detDef.token := imgL.FileInfo;
                imgL[j].DetectorDefineList.Add(detDef);
              end;
        end;

      tokens := imgMat.DetectorTokens;
      DoStatus('总共有 %d 个分类', [length(tokens)]);
      for n in tokens do
          DoStatus('"%s" 有 %d 张图片', [n.Text, imgMat.GetDetectorTokenCount(n)]);

      TThread.Synchronize(Sender, procedure
        begin
          Training_IMGClassifier_Button.Enabled := True;
          TestClassifierButton.Enabled := True;
          ResetButton.Enabled := True;
        end);
    end);
end;

procedure TLargeMetricImgClassifierForm.ResetButtonClick(Sender: TObject);
  procedure d(FileName: U_String);
  begin
    DoStatus('删除文件 %s', [FileName.Text]);
    umlDeleteFile(FileName);
  end;

begin
  d(umlCombineFileName(TPath.GetLibraryPath, 'LMetric_mnist_number_0_9.imgMat.sync'));
  d(umlCombineFileName(TPath.GetLibraryPath, 'LMetric_mnist_number_0_9.imgMat.sync_'));
  d(umlCombineFileName(TPath.GetLibraryPath, 'LMetric_mnist_number_0_9' + C_LMetric_Ext));
  d(umlCombineFileName(TPath.GetLibraryPath, 'LMetric_mnist_number_0_9.matrix'));
end;

procedure TLargeMetricImgClassifierForm.Timer1Timer(Sender: TObject);
begin
  DoStatus;
end;

end.
