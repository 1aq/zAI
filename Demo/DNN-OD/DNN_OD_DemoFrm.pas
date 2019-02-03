unit DNN_OD_DemoFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation,
  FMX.StdCtrls, FMX.Objects, FMX.ScrollBox, FMX.Memo,

  System.IOUtils,

  CoreClasses,
  Learn, LearnTypes,
  zAI, zAI_Common, zAI_TrainingTask,
  zDrawEngineInterface_SlowFMX, zDrawEngine, Geometry2DUnit, MemoryRaster,
  MemoryStream64, PascalStrings, UnicodeMixedLib, DoStatusIO, FMX.Layouts, FMX.ExtCtrls;

type
  TDNN_OD_Form = class(TForm)
    DNN_OD_Button: TButton;
    Memo1: TMemo;
    Timer1: TTimer;
    Image1: TImageViewer;
    ResetButton: TButton;
    procedure DNN_OD_ButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ResetButtonClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    procedure DoStatusMethod(AText: SystemString; const ID: Integer);
  public
  end;

var
  DNN_OD_Form: TDNN_OD_Form;

implementation

{$R *.fmx}


procedure TDNN_OD_Form.DNN_OD_ButtonClick(Sender: TObject);
begin
  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    var
      bear_ImgL: TAI_ImageList;
      bear_dataset_file, bear_od_file: U_String;
      i, j: Integer;
      detDef: TAI_DetectorDefine;

      ai: TAI;
      param: PMMOD_Train_Parameter;

      m64: TMemoryStream64;

      mmod_hnd: TMMOD_Handle;
      matrix_img: TMatrix_Image_Handle;
      detTarget: TMemoryRaster;
      tk: TTimeTick;
      mmod_processcounter: Integer;
    begin
      TThread.Synchronize(Sender, procedure
        begin
          DNN_OD_Button.Enabled := False;
        end);
      try
        bear_dataset_file := umlCombineFileName(TPath.GetLibraryPath, 'bear.ImgDataSet');
        bear_od_file := umlChangeFileExt(bear_dataset_file, zAI.C_MMOD_Ext);

        bear_ImgL := TAI_ImageList.Create;
        bear_ImgL.LoadFromFile(bear_dataset_file);

        ai := TAI.OpenEngine();

        DoStatus('����ܱ��ܵ�OD����� : %s', [bear_od_file.Text]);
        if not umlFileExists(bear_od_file) then
          begin
            DoStatus('��ʼѵ���ܱ��ܵ�OD�����.');

            for i := 0 to bear_ImgL.Count - 1 do
              for j := 0 to bear_ImgL[i].DetectorDefineList.Count - 1 do
                begin
                  detDef := bear_ImgL[i].DetectorDefineList[j];
                  // ����߶Ƚ���
                  // �ó߶��ǵȱȳ߶ȣ�100:100�ǿ�߱ȣ���������ʵ��100���أ�100:100Ҳ��ͬ��1:1
                  // �����100:100���Ǹ��߽���������������Ҫ�Ƿ�������������ҰѼ��������ȫ���ĳɷ�����

                  // MMODҲ���Խ���DNN-OD
                  // MMOD���SVM-OD��������ǩ
                  // ������detDef.Token�ж���ı�ǩ���ᱻDNN�����ѧϰ(����)
                  detDef.R := detDef.Owner.Raster.ComputeAreaScaleSpace(detDef.R, 100, 100);
                end;

            param := ai.MMOD_DNN_PrepareTrain(bear_ImgL, umlChangeFileExt(bear_dataset_file, '.sync'));

            // �����ODѵ��������������������Ƴ���

            // �������г�����������Ҫ�ļ���DNN OD����
            // ���粻̫���ף������в���������ϣ��ؼ���
            // "resnet mini batch"
            // "resnet object detector"

            // ����ѵ���ļƻ�ʱ��Ϊ2Сʱ
            param^.timeout := C_Tick_Hour * 2;

            // ����ϣ�����ѵ�����ļ����������ߴ�100
            param^.target_size := 100;
            // ����ϣ�����ѵ�����ļ�������ڵ���С�ߴ�������50
            param^.min_target_size := 50;
            // ����resnet mini batch���ɵ�Ŀ�����߶�,�ü���Ķ����������������98����
            // min_object_size_x ��Ӧ�ó��� target_size����һ�������������ZAI�ں˻��Զ�У�������ǻ�����ܶ���ʾ
            param^.min_object_size_x := 98;
            // ����resnet mini batch���ɵ�Ŀ�����߶�,���ü��Ķ�����������̱�������49����
            // min_object_size_y ��Ӧ�ó��� min_target_size����һ�������������ZAI�ں˻��Զ�У�������ǻ�����ܶ���ʾ
            param^.min_object_size_y := 49;

            // resnet mini batch �߶�
            // ѵ���У�ÿ��step input net����ʹ��renet mini batch��������һ����������
            // ����Ĳ����������������ĳ߶�
            param^.chip_dims_x := 300;
            param^.chip_dims_y := 300;

            // ������ȣ�ֵԽСѵ���ٶ�Խ�죬ֵԽ��ѵ�����Խ��ȷ��������Ҫ������ʱ����ѵ��
            // ��ȡ��ֵ�ܴ���ˣ�ѵ���������ܱ��ܵ����ݼ�����Ҫ30��������
            param^.iterations_without_progress_threshold := 500;

            // resnet��ÿ��step��mini batch�Ĵ���
            // һ����˵���������ͼƬ�ܺ�ֵ֮��Ϳ����ˣ��������ͼƬ�ܶ࣬��С���Ը���GPU+�ڴ����������
            param^.num_crops := 10;

            // resnet����mini batchʱ�������תϵ��
            param^.max_rotation_degrees := 90;

            // ���ڣ������Ѿ������ζ���������ˣ������ǿ�ʼִ��ѵ����
            // MMODҲ���Խ���DNN-OD
            // MMOD���SVM-OD��������ǩ
            // ������detDef.Token�ж���ı�ǩ���ᱻDNN�����ѧϰ(����)
            m64 := ai.MMOD_DNN_Train_Stream(param);

            if m64 <> nil then
              begin
                DoStatus('ѵ�����');
                m64.SaveToFile(bear_od_file);
                disposeObject(m64);
              end
            else
                DoStatus('ѵ��ʧ��');

            ai.Free_MMOD_DNN_TrainParam(param);
          end;

        if umlFileExists(bear_od_file) then
          begin
            DoStatus('�����ܱ��ܵ�OD����� : %s', [bear_od_file.Text]);
            mmod_hnd := ai.MMOD_DNN_Open_Stream(bear_od_file);

            // ʹ��texture atlas������ϵ�������դ����������������¹�դ
            detTarget := bear_ImgL.PackingRaster;

            // ���ڼ����ʾ�����ﶼ���������OD���ʵ���ˣ�ֱ��ʹ��DrawMMOD�����
            ai.DrawMMOD(mmod_hnd, detTarget, DEColor(0.5, 0.5, 1, 1));

            TThread.Synchronize(Sender, procedure
              begin
                MemoryBitmapToBitmap(detTarget, Image1.Bitmap);
              end);

            // �������ǲ���һ��gpu��od����
            // ��ʵ��Ӧ���У�����Ҳ���Ƶ��ʹ�����api
            DoStatus('����GPU-���ܲ��ԣ���դ�������ķֱ���Ϊ %d * %d', [detTarget.width, detTarget.height]);
            DoStatus('����GPU-���ܲ��ԣ�������GPU-OD���ܲ���,5��󽫻ᱨ����Խ��.');
            tk := GetTimeTick();
            mmod_processcounter := 0;
            while GetTimeTick() - tk < 5000 do
              begin
                // ��MMOD_DNN_Process�ķ������飬TMMOD_Desc�У�����token��ǩ������ʾ����⵽�����������ʲô
                // ע�⣺MMOD_DNN_Process��ÿ�δ���ǰ���Ὣ�ڴ�Ĺ�դ�����ݸ�gpu����������ǵȴ������ܲ��У�������Ҫ����ƿ��
                // ע�⣺������Ҫ��ǳ��ߵ�ʵʱ�ԣ����Ǿ���Ҫ���ֱ��ʵ���һ�㣬����ʹ��Tracker�����������ٸ��ٶ�λ
                // ע�⣺������Ҫ��ǳ��ߵ�ʵʱ�ԣ�����Ҳ����ʹ��TAI_Parallel���������л��Ĵ�����������OD��⣬�Դ�������Ч��
                ai.MMOD_DNN_Process(mmod_hnd, detTarget);
                inc(mmod_processcounter);
              end;
            DoStatus('����GPU-���ܲ��ԣ�GPU-OD��5�����ܹ������ %d ��OD��⣬��Լÿ����� %d �μ��', [mmod_processcounter, Round(mmod_processcounter / 5.0)]);

            matrix_img := ai.Prepare_Matrix_Image(detTarget);
            DoStatus('����GPU-���ܲ��ԣ���դ�������ķֱ���Ϊ %d * %d', [detTarget.width, detTarget.height]);
            DoStatus('����GPU-���ܲ��ԣ�������GPU-OD���ܲ���,5��󽫻ᱨ����Խ��.');
            tk := GetTimeTick();
            mmod_processcounter := 0;
            while GetTimeTick() - tk < 5000 do
              begin
                // ��MMOD_DNN_Process�ķ������飬TMMOD_Desc�У�����token��ǩ������ʾ����⵽�����������ʲô
                // ע�⣺MMOD_DNN_Process��ÿ�δ���ǰ���Ὣ�ڴ�Ĺ�դ�����ݸ�gpu����������ǵȴ������ܲ��У�������Ҫ����ƿ��
                // ע�⣺������Ҫ��ǳ��ߵ�ʵʱ�ԣ����Ǿ���Ҫ���ֱ��ʵ���һ�㣬����ʹ��Tracker�����������ٸ��ٶ�λ
                // ע�⣺������Ҫ��ǳ��ߵ�ʵʱ�ԣ�����Ҳ����ʹ��TAI_Parallel���������л��Ĵ�����������OD��⣬�Դ�������Ч��
                ai.MMOD_DNN_Process_Matrix(mmod_hnd, matrix_img);
                inc(mmod_processcounter);
              end;
            DoStatus('����GPU-���ܲ��ԣ�GPU-OD��5�����ܹ������ %d ��OD��⣬��Լÿ����� %d �μ��', [mmod_processcounter, Round(mmod_processcounter / 5.0)]);
            ai.Close_Matrix_Image(matrix_img);

            // ���ڣ����ǽ��ֱ��ʽ��ͣ�����һ������
            detTarget.Scale(0.5);

            // �������ǲ���һ��gpu��od����
            // ��ʵ��Ӧ���У�����Ҳ���Ƶ��ʹ�����api
            DoStatus('����GPU-���ܲ��ԣ���դ�������ķֱ���Ϊ %d * %d', [detTarget.width, detTarget.height]);
            DoStatus('����GPU-���ܲ��ԣ�������GPU-OD���ܲ���,5��󽫻ᱨ����Խ��.');
            tk := GetTimeTick();
            mmod_processcounter := 0;
            while GetTimeTick() - tk < 5000 do
              begin
                // ��MMOD_DNN_Process�ķ������飬TMMOD_Desc�У�����token��ǩ������ʾ����⵽�����������ʲô
                // ע�⣺MMOD_DNN_Process��ÿ�δ���ǰ���Ὣ�ڴ�Ĺ�դ�����ݸ�gpu����������ǵȴ������ܲ��У�������Ҫ����ƿ��
                // ע�⣺������Ҫ��ǳ��ߵ�ʵʱ�ԣ����Ǿ���Ҫ���ֱ��ʵ���һ�㣬����ʹ��Tracker�����������ٸ��ٶ�λ
                // ע�⣺������Ҫ��ǳ��ߵ�ʵʱ�ԣ�����Ҳ����ʹ��TAI_Parallel���������л��Ĵ�����������OD��⣬�Դ�������Ч��
                ai.MMOD_DNN_Process(mmod_hnd, detTarget);
                inc(mmod_processcounter);
              end;
            DoStatus('����GPU-���ܲ��ԣ�GPU-OD��5�����ܹ������ %d ��OD��⣬��Լÿ����� %d �μ��', [mmod_processcounter, Round(mmod_processcounter / 5.0)]);

            matrix_img := ai.Prepare_Matrix_Image(detTarget);
            DoStatus('����GPU-���ܲ��ԣ���դ�������ķֱ���Ϊ %d * %d', [detTarget.width, detTarget.height]);
            DoStatus('����GPU-���ܲ��ԣ�������GPU-OD���ܲ���,5��󽫻ᱨ����Խ��.');
            tk := GetTimeTick();
            mmod_processcounter := 0;
            while GetTimeTick() - tk < 5000 do
              begin
                // ��MMOD_DNN_Process�ķ������飬TMMOD_Desc�У�����token��ǩ������ʾ����⵽�����������ʲô
                // ע�⣺MMOD_DNN_Process��ÿ�δ���ǰ���Ὣ�ڴ�Ĺ�դ�����ݸ�gpu����������ǵȴ������ܲ��У�������Ҫ����ƿ��
                // ע�⣺������Ҫ��ǳ��ߵ�ʵʱ�ԣ����Ǿ���Ҫ���ֱ��ʵ���һ�㣬����ʹ��Tracker�����������ٸ��ٶ�λ
                // ע�⣺������Ҫ��ǳ��ߵ�ʵʱ�ԣ�����Ҳ����ʹ��TAI_Parallel���������л��Ĵ�����������OD��⣬�Դ�������Ч��
                ai.MMOD_DNN_Process_Matrix(mmod_hnd, matrix_img);
                inc(mmod_processcounter);
              end;
            DoStatus('����GPU-���ܲ��ԣ�GPU-OD��5�����ܹ������ %d ��OD��⣬��Լÿ����� %d �μ��', [mmod_processcounter, Round(mmod_processcounter / 5.0)]);
            ai.Close_Matrix_Image(matrix_img);

            ai.MMOD_DNN_Close(mmod_hnd);
          end;

        disposeObject(bear_ImgL);
        disposeObject(ai);

      finally
          TThread.Synchronize(Sender, procedure
          begin
            DNN_OD_Button.Enabled := True;
          end);
      end;
    end);
end;

procedure TDNN_OD_Form.DoStatusMethod(AText: SystemString; const ID: Integer);
begin
  Memo1.Lines.Add(AText);
  Memo1.GoToTextEnd;
end;

procedure TDNN_OD_Form.FormCreate(Sender: TObject);
begin
  AddDoStatusHook(Self, DoStatusMethod);
  // ��ȡzAI������
  ReadAIConfig;
  // ��һ��������Key����������֤ZAI��Key
  // ���ӷ�������֤Key������������ʱһ���Ե���֤��ֻ�ᵱ��������ʱ�Ż���֤��������֤����ͨ����zAI����ܾ�����
  // �ڳ��������У���������TAI�����ᷢ��Զ����֤
  // ��֤��Ҫһ��userKey��ͨ��userkey�����ZAI������ʱ���ɵ����Key��userkey����ͨ��web���룬Ҳ������ϵ���߷���
  // ��֤key���ǿ����Ӽ����޷����ƽ�
  zAI.Prepare_AI_Engine();
end;

procedure TDNN_OD_Form.ResetButtonClick(Sender: TObject);
var
  fn: U_String;

  procedure d(filename: U_String);
  begin
    DoStatus('ɾ���ļ� %s', [filename.Text]);
    umlDeleteFile(filename);
  end;

begin
  fn := umlCombineFileName(TPath.GetLibraryPath, 'bear' + zAI.C_MMOD_Ext);
  d(fn);
  d(umlChangeFileExt(fn, '.sync'));
  d(umlChangeFileExt(fn, '.sync_'));
  Image1.Bitmap.FreeHandle;
end;

procedure TDNN_OD_Form.Timer1Timer(Sender: TObject);
begin
  DoStatus;
end;

end.
